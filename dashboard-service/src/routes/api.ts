import { Router, Request, Response } from 'express';
import { prisma, createServiceLogger } from 'shared';
import axios from 'axios';

const router = Router();
const logger = createServiceLogger('dashboard-api');

const LOGGER_URL = process.env.LOGGER_URL || 'http://localhost:3002';

// Get all endpoints for a user
router.get('/endpoints', async (req: Request, res: Response) => {
  try {
    const apiKey = req.headers['x-api-key'] as string;

    if (!apiKey) {
      return res.status(401).json({ error: 'API key required' });
    }

    const user = await prisma.user.findUnique({
      where: { apiKey },
      include: {
        endpoints: {
          include: {
            stats: {
              orderBy: { date: 'desc' },
              take: 7,
            },
          },
        },
      },
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid API key' });
    }

    res.json({ endpoints: user.endpoints });
  } catch (error) {
    logger.error('Error fetching endpoints', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create new endpoint
router.post('/endpoints', async (req: Request, res: Response) => {
  try {
    const apiKey = req.headers['x-api-key'] as string;
    const { name, destinationUrl, secret } = req.body;

    if (!apiKey) {
      return res.status(401).json({ error: 'API key required' });
    }

    if (!name || !destinationUrl) {
      return res.status(400).json({ error: 'Name and destination URL required' });
    }

    const user = await prisma.user.findUnique({
      where: { apiKey },
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid API key' });
    }

    const endpoint = await prisma.endpoint.create({
      data: {
        userId: user.id,
        name,
        destinationUrl,
        secret,
      },
    });

    res.status(201).json({ endpoint });
  } catch (error) {
    logger.error('Error creating endpoint', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get webhook events for an endpoint
router.get('/endpoints/:endpointId/events', async (req: Request, res: Response) => {
  try {
    const { endpointId } = req.params;
    const { limit = '50', offset = '0', status } = req.query;

    const where: any = { endpointId };
    if (status) {
      where.status = status;
    }

    const [events, total] = await Promise.all([
      prisma.webhookEvent.findMany({
        where,
        include: {
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
    logger.error('Error fetching events', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get event details with logs
router.get('/events/:eventId', async (req: Request, res: Response) => {
  try {
    const { eventId } = req.params;

    // Fetch from logger service
    const response = await axios.get(`${LOGGER_URL}/logs/events/${eventId}`);
    res.json(response.data);
  } catch (error) {
    logger.error('Error fetching event details', { error });
    if (axios.isAxiosError(error) && error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

// Get endpoint statistics
router.get('/endpoints/:endpointId/stats', async (req: Request, res: Response) => {
  try {
    const { endpointId } = req.params;
    const { days = '7' } = req.query;

    const response = await axios.get(`${LOGGER_URL}/logs/stats/${endpointId}`, {
      params: { days },
    });

    res.json(response.data);
  } catch (error) {
    logger.error('Error fetching stats', { error });
    if (axios.isAxiosError(error) && error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

// Update endpoint
router.patch('/endpoints/:endpointId', async (req: Request, res: Response) => {
  try {
    const { endpointId } = req.params;
    const { name, destinationUrl, secret, isActive } = req.body;

    const data: any = {};
    if (name !== undefined) data.name = name;
    if (destinationUrl !== undefined) data.destinationUrl = destinationUrl;
    if (secret !== undefined) data.secret = secret;
    if (isActive !== undefined) data.isActive = isActive;

    const endpoint = await prisma.endpoint.update({
      where: { id: endpointId },
      data,
    });

    res.json({ endpoint });
  } catch (error) {
    logger.error('Error updating endpoint', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete endpoint
router.delete('/endpoints/:endpointId', async (req: Request, res: Response) => {
  try {
    const { endpointId } = req.params;

    await prisma.endpoint.delete({
      where: { id: endpointId },
    });

    res.json({ success: true });
  } catch (error) {
    logger.error('Error deleting endpoint', { error });
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;

// Made with Bob
