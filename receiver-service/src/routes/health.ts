import { Router, Request, Response } from 'express';
import { prisma, redisQueue } from 'shared';

const router = Router();

router.get('/', async (req: Request, res: Response) => {
  try {
    // Check database connection
    await prisma.$queryRaw`SELECT 1`;
    
    // Check Redis connection
    await redisQueue.enqueue('health_check', {
      type: 'webhook',
      eventId: 'health',
      endpointId: 'health',
      destinationUrl: 'health',
      payloadS3Key: 'health',
      attemptNumber: 0,
    });

    res.json({
      status: 'healthy',
      service: 'receiver',
      timestamp: new Date().toISOString(),
      checks: {
        database: 'ok',
        redis: 'ok',
      },
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      service: 'receiver',
      timestamp: new Date().toISOString(),
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
});

router.get('/ready', async (req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ready: true });
  } catch (error) {
    res.status(503).json({ ready: false });
  }
});

router.get('/live', (req: Request, res: Response) => {
  res.json({ alive: true });
});

export default router;

// Made with Bob
