import axios, { AxiosError } from 'axios';
import { prisma, s3Storage, createServiceLogger, QueueMessage, redisQueue } from 'shared';

const logger = createServiceLogger('forwarder');

const MAX_RETRY_ATTEMPTS = parseInt(process.env.MAX_RETRY_ATTEMPTS || '3');
const RETRY_DELAY_MS = parseInt(process.env.RETRY_DELAY_MS || '300000'); // 5 minutes
const RETRY_BACKOFF_MULTIPLIER = parseInt(process.env.RETRY_BACKOFF_MULTIPLIER || '2');

export class WebhookForwarder {
  async forward(message: QueueMessage): Promise<void> {
    const startTime = Date.now();
    const { eventId, destinationUrl, payloadS3Key, attemptNumber } = message;

    try {
      logger.info('Forwarding webhook', {
        eventId,
        destinationUrl,
        attemptNumber,
      });

      // Update event status to forwarding
      await prisma.webhookEvent.update({
        where: { id: eventId },
        data: { status: 'forwarding' },
      });

      // Get payload from S3
      const payload = await s3Storage.getPayload(payloadS3Key);

      // Forward webhook
      const response = await axios({
        method: payload.method || 'POST',
        url: destinationUrl,
        data: payload.body,
        headers: {
          ...payload.headers,
          'User-Agent': 'WebhookRelay/1.0',
          'X-Webhook-Event-Id': eventId,
          'X-Webhook-Attempt': attemptNumber.toString(),
        },
        timeout: 30000, // 30 seconds
        validateStatus: () => true, // Don't throw on any status
      });

      const duration = Date.now() - startTime;
      const success = response.status >= 200 && response.status < 300;

      // Store response in S3
      const responseS3Key = s3Storage.generateKey('responses', eventId);
      await s3Storage.uploadPayload(responseS3Key, {
        statusCode: response.status,
        headers: response.headers,
        body: response.data,
        duration,
      });

      // Create delivery attempt record
      await prisma.deliveryAttempt.create({
        data: {
          eventId,
          attemptNumber,
          status: success ? 'success' : 'failed',
          responseCode: response.status,
          responseS3Key,
          errorMessage: success ? null : `HTTP ${response.status}`,
        },
      });

      if (success) {
        // Mark as delivered
        await prisma.webhookEvent.update({
          where: { id: eventId },
          data: {
            status: 'delivered',
            forwardedAt: new Date(),
          },
        });

        // Update stats
        await this.updateStats(message.endpointId, true, duration);

        logger.info('Webhook delivered successfully', {
          eventId,
          statusCode: response.status,
          duration,
        });
      } else {
        // Handle failure
        await this.handleFailure(message, response.status, duration);
      }
    } catch (error) {
      const duration = Date.now() - startTime;
      await this.handleError(message, error, duration);
    }
  }

  private async handleFailure(
    message: QueueMessage,
    statusCode: number,
    duration: number
  ): Promise<void> {
    const { eventId, attemptNumber, endpointId } = message;

    logger.warn('Webhook delivery failed', {
      eventId,
      statusCode,
      attemptNumber,
    });

    if (attemptNumber < MAX_RETRY_ATTEMPTS) {
      // Schedule retry
      const delaySeconds = RETRY_DELAY_MS * Math.pow(RETRY_BACKOFF_MULTIPLIER, attemptNumber - 1) / 1000;
      const nextRetryAt = new Date(Date.now() + delaySeconds * 1000);

      await prisma.deliveryAttempt.updateMany({
        where: {
          eventId,
          attemptNumber,
        },
        data: {
          nextRetryAt,
        },
      });

      await redisQueue.scheduleRetry(
        {
          ...message,
          type: 'retry',
          attemptNumber: attemptNumber + 1,
        },
        delaySeconds
      );

      logger.info('Scheduled retry', {
        eventId,
        nextAttempt: attemptNumber + 1,
        delaySeconds,
      });
    } else {
      // Max retries reached
      await prisma.webhookEvent.update({
        where: { id: eventId },
        data: { status: 'failed' },
      });

      await this.updateStats(endpointId, false, duration);

      logger.error('Max retries reached', {
        eventId,
        attempts: attemptNumber,
      });
    }
  }

  private async handleError(
    message: QueueMessage,
    error: unknown,
    duration: number
  ): Promise<void> {
    const { eventId, attemptNumber, endpointId } = message;
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';

    logger.error('Error forwarding webhook', {
      eventId,
      error: errorMessage,
      attemptNumber,
    });

    // Store error in S3
    const errorS3Key = s3Storage.generateKey('errors', eventId);
    await s3Storage.uploadPayload(errorS3Key, {
      error: errorMessage,
      stack: error instanceof Error ? error.stack : undefined,
      timestamp: new Date().toISOString(),
    });

    // Create delivery attempt record
    await prisma.deliveryAttempt.create({
      data: {
        eventId,
        attemptNumber,
        status: 'failed',
        responseS3Key: errorS3Key,
        errorMessage,
      },
    });

    if (attemptNumber < MAX_RETRY_ATTEMPTS) {
      // Schedule retry
      const delaySeconds = RETRY_DELAY_MS * Math.pow(RETRY_BACKOFF_MULTIPLIER, attemptNumber - 1) / 1000;
      
      await redisQueue.scheduleRetry(
        {
          ...message,
          type: 'retry',
          attemptNumber: attemptNumber + 1,
        },
        delaySeconds
      );
    } else {
      // Max retries reached
      await prisma.webhookEvent.update({
        where: { id: eventId },
        data: { status: 'failed' },
      });

      await this.updateStats(endpointId, false, duration);
    }
  }

  private async updateStats(
    endpointId: string,
    success: boolean,
    duration: number
  ): Promise<void> {
    try {
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      const stats = await prisma.endpointStats.findUnique({
        where: {
          endpointId_date: {
            endpointId,
            date: today,
          },
        },
      });

      const currentAvg = stats?.avgResponseTime || 0;
      const currentTotal = (stats?.totalDelivered || 0) + (stats?.totalFailed || 0);
      const newAvg = currentTotal > 0
        ? Math.round((currentAvg * currentTotal + duration) / (currentTotal + 1))
        : duration;

      await prisma.endpointStats.upsert({
        where: {
          endpointId_date: {
            endpointId,
            date: today,
          },
        },
        update: {
          totalDelivered: success ? { increment: 1 } : undefined,
          totalFailed: success ? undefined : { increment: 1 },
          avgResponseTime: newAvg,
        },
        create: {
          endpointId,
          date: today,
          totalReceived: 0,
          totalDelivered: success ? 1 : 0,
          totalFailed: success ? 0 : 1,
          avgResponseTime: duration,
        },
      });
    } catch (error) {
      logger.error('Error updating stats', { error, endpointId });
    }
  }
}

// Made with Bob
