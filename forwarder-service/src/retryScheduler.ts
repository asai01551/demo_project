import { createServiceLogger, redisQueue } from 'shared';
import { WebhookForwarder } from './forwarder';

const logger = createServiceLogger('retry-scheduler');

export class RetryScheduler {
  private intervalId?: NodeJS.Timeout;
  private isRunning: boolean = false;
  private forwarder: WebhookForwarder;

  constructor(forwarder: WebhookForwarder) {
    this.forwarder = forwarder;
  }

  start(): void {
    if (this.isRunning) {
      logger.warn('Retry scheduler already running');
      return;
    }

    this.isRunning = true;
    logger.info('Starting retry scheduler');

    // Check for retries every 30 seconds
    this.intervalId = setInterval(() => {
      this.processRetries();
    }, 30000);

    // Process immediately on start
    this.processRetries();
  }

  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = undefined;
    }
    this.isRunning = false;
    logger.info('Retry scheduler stopped');
  }

  private async processRetries(): Promise<void> {
    try {
      const messages = await redisQueue.getRetryMessages();

      if (messages.length > 0) {
        logger.info(`Processing ${messages.length} retry messages`);

        for (const message of messages) {
          try {
            await this.forwarder.forward(message);
          } catch (error) {
            logger.error('Error processing retry message', {
              error,
              eventId: message.eventId,
            });
          }
        }
      }
    } catch (error) {
      logger.error('Error in retry scheduler', { error });
    }
  }
}

// Made with Bob
