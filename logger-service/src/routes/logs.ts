import { Router, Request, Response } from 'express';
import { prisma, s3Storage, createServiceLogger } from 'shared';

const router = Router();
const logger = createServiceLogger('logger-logs');

// Get logs for a specific event
router.get('/events/:eventId', async (req: Request, res: Response) => {
  try {
    const { eventId } = req.params;

    const event = await prisma.webhookEvent.findUnique({
      where: { id: eventId },
      include: {
        endpoint: {
          select: {
            id: true,
            name: true,
            destinationUrl: true,
          },
        },
        deliveryAttempts: {
          orderBy: { attemptedAt: 'desc' },
        },
        logs: {
          orderBy: { loggedAt: 'desc' },
        },
      },
    });

    if (!event) {
      return res.status(404).json({ error: 'Event not found' });
    }

    // Get payload from S3
    const payload = await s3Storage.getPayload(event.payloadS3Key);

    res.json({
      event: {
        id: event.id,
        status: event.status,
        receivedAt: event.receivedAt,
        forwardedAt: event.forwardedAt,
        method: event.method,
        headers: event.headers,
      },
      endpoint: event.endpoint,
      payload,
      attempts: event.deliveryAttempts,
      logs: event.logs,
    });
  } catch (error) {
    logger.error('Error fetching event logs', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get payload from S3
router.get('/payload/:s3Key', async (req: Request, res: Response) => {
  try {
    const { s3Key } = req.params;
    const payload = await s3Storage.getPayload(s3Key);
    res.json(payload);
  } catch (error) {
    logger.error('Error fetching payload', { error });
    res.status(500).json({ error: 'Failed to fetch payload' });
  }
});

// Get response from S3
router.get('/response/:s3Key', async (req: Request, res: Response) => {
  try {
    const { s3Key } = req.params;
    const response = await s3Storage.getPayload(s3Key);
    res.json(response);
  } catch (error) {
    logger.error('Error fetching response', { error });
    res.status(500).json({ error: 'Failed to fetch response' });
  }
});

// Search logs
router.get('/search', async (req: Request, res: Response) => {
  try {
    const {
      endpointId,
      status,
      startDate,
      endDate,
      limit = '50',
      offset = '0',
    } = req.query;

    const where: any = {};

    if (endpointId) {
      where.endpointId = endpointId as string;
    }

    if (status) {
      where.status = status as string;
    }

    if (startDate || endDate) {
      where.receivedAt = {};
      if (startDate) {
        where.receivedAt.gte = new Date(startDate as string);
      }
      if (endDate) {
        where.receivedAt.lte = new Date(endDate as string);
      }
    }

    const [events, total] = await Promise.all([
      prisma.webhookEvent.findMany({
        where,
        include: {
          endpoint: {
            select: {
              id: true,
              name: true,
              destinationUrl: true,
            },
          },
          deliveryAttempts: {
            orderBy: { attemptedAt: 'desc' },
            take: 1,
          },
        },
        orderBy: { receivedAt: 'desc' },
        take: parseInt(limit as string),
        skip: parseInt(offset as string),
      }),
      prisma.webhookEvent.count({ where }),
    ]);

    res.json({
      events,
      pagination: {
        total,
        limit: parseInt(limit as string),
        offset: parseInt(offset as string),
      },
    });
  } catch (error) {
    logger.error('Error searching logs', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get endpoint statistics
router.get('/stats/:endpointId', async (req: Request, res: Response) => {
  try {
    const { endpointId } = req.params;
    const { days = '7' } = req.query;

    const startDate = new Date();
    startDate.setDate(startDate.getDate() - parseInt(days as string));
    startDate.setHours(0, 0, 0, 0);

    const stats = await prisma.endpointStats.findMany({
      where: {
        endpointId,
        date: {
          gte: startDate,
        },
      },
      orderBy: { date: 'asc' },
    });

    res.json({ stats });
  } catch (error) {
    logger.error('Error fetching stats', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;

// Made with Bob
