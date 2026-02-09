import { Router, Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { prisma, redisQueue, s3Storage, createServiceLogger, QueueMessage } from 'shared';

const router = Router();
const logger = createServiceLogger('receiver-webhook');

// Middleware to validate API key and get endpoint
const validateEndpoint = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const endpointId = req.params.endpointId;
    const apiKey = req.headers['x-api-key'] as string;

    if (!apiKey) {
      return res.status(401).json({ error: 'API key required' });
    }

    // Find user by API key
    const user = await prisma.user.findUnique({
      where: { apiKey },
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid API key' });
    }

    // Find endpoint
    const endpoint = await prisma.endpoint.findFirst({
      where: {
        id: endpointId,
        userId: user.id,
        isActive: true,
      },
    });

    if (!endpoint) {
      return res.status(404).json({ error: 'Endpoint not found or inactive' });
    }

    // Attach to request
    (req as any).endpoint = endpoint;
    (req as any).user = user;
    next();
  } catch (error) {
    logger.error('Error validating endpoint', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Receive webhook
router.post('/:endpointId', validateEndpoint, async (req: Request, res: Response) => {
  const startTime = Date.now();
  const eventId = uuidv4();
  const endpoint = (req as any).endpoint;

  try {
    logger.info('Webhook received', {
      eventId,
      endpointId: endpoint.id,
      method: req.method,
    });

    // Extract headers (exclude sensitive ones)
    const headers: Record<string, string> = {};
    Object.keys(req.headers).forEach((key) => {
      if (!['authorization', 'x-api-key'].includes(key.toLowerCase())) {
        headers[key] = req.headers[key] as string;
      }
    });

    // Store payload in S3
    const payloadS3Key = s3Storage.generateKey('payloads', eventId);
    await s3Storage.uploadPayload(payloadS3Key, {
      body: req.body,
      headers,
      method: req.method,
      query: req.query,
    });

    // Create webhook event in database
    const webhookEvent = await prisma.webhookEvent.create({
      data: {
        id: eventId,
        endpointId: endpoint.id,
        payloadS3Key,
        headers,
        method: req.method,
        status: 'pending',
      },
    });

    // Enqueue for forwarding
    const queueMessage: QueueMessage = {
      type: 'webhook',
      eventId: webhookEvent.id,
      endpointId: endpoint.id,
      destinationUrl: endpoint.destinationUrl,
      payloadS3Key,
      attemptNumber: 1,
      headers,
    };

    await redisQueue.enqueue('webhook_queue', queueMessage);

    // Update stats
    await updateEndpointStats(endpoint.id);

    const duration = Date.now() - startTime;
    logger.info('Webhook accepted', {
      eventId,
      endpointId: endpoint.id,
      duration,
    });

    // Return success immediately
    res.status(202).json({
      success: true,
      eventId: webhookEvent.id,
      message: 'Webhook accepted for processing',
    });
  } catch (error) {
    logger.error('Error processing webhook', { error, eventId });
    res.status(500).json({
      success: false,
      error: 'Failed to process webhook',
    });
  }
});

// Get webhook status
router.get('/:endpointId/events/:eventId', validateEndpoint, async (req: Request, res: Response) => {
  try {
    const { eventId } = req.params;
    const endpoint = (req as any).endpoint;

    const event = await prisma.webhookEvent.findFirst({
      where: {
        id: eventId,
        endpointId: endpoint.id,
      },
      include: {
        deliveryAttempts: {
          orderBy: { attemptedAt: 'desc' },
        },
      },
    });

    if (!event) {
      return res.status(404).json({ error: 'Event not found' });
    }

    res.json({
      id: event.id,
      status: event.status,
      receivedAt: event.receivedAt,
      forwardedAt: event.forwardedAt,
      attempts: event.deliveryAttempts.length,
      lastAttempt: event.deliveryAttempts[0] || null,
    });
  } catch (error) {
    logger.error('Error fetching event status', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Helper function to update endpoint stats
async function updateEndpointStats(endpointId: string): Promise<void> {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    await prisma.endpointStats.upsert({
      where: {
        endpointId_date: {
          endpointId,
          date: today,
        },
      },
      update: {
        totalReceived: { increment: 1 },
      },
      create: {
        endpointId,
        date: today,
        totalReceived: 1,
        totalDelivered: 0,
        totalFailed: 0,
      },
    });
  } catch (error) {
    logger.error('Error updating endpoint stats', { error, endpointId });
  }
}

export default router;

// Made with Bob
