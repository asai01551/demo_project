import dotenv from 'dotenv';
import path from 'path';
import { createServiceLogger, connectDatabase, redisQueue } from 'shared';
import { WebhookForwarder } from './forwarder';
import { RetryScheduler } from './retryScheduler';

// Load .env from project root
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const logger = createServiceLogger('forwarder-service');

class ForwarderService {
  private forwarder: WebhookForwarder;
  private retryScheduler: RetryScheduler;
  private isRunning: boolean = false;

  constructor() {
    this.forwarder = new WebhookForwarder();
    this.retryScheduler = new RetryScheduler(this.forwarder);
  }

  async start(): Promise<void> {
    try {
      await connectDatabase();
      logger.info('Forwarder service starting...');

      this.isRunning = true;

      // Start processing webhooks from queue
      this.processWebhookQueue();

      // Start retry scheduler
      this.retryScheduler.start();

      logger.info('Forwarder service started successfully');
    } catch (error) {
      logger.error('Failed to start forwarder service', { error });
      process.exit(1);
    }
  }

  private async processWebhookQueue(): Promise<void> {
    while (this.isRunning) {
      try {
        const message = await redisQueue.dequeue('webhook_queue', 5);

        if (message) {
          logger.info('Processing webhook from queue', {
            eventId: message.eventId,
            attemptNumber: message.attemptNumber,
          });

          await this.forwarder.forward(message);
        }
      } catch (error) {
        logger.error('Error processing webhook queue', { error });
        // Wait a bit before retrying to avoid tight loop on persistent errors
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
  }

  async stop(): Promise<void> {
    logger.info('Stopping forwarder service...');
    this.isRunning = false;
    this.retryScheduler.stop();
    await redisQueue.disconnect();
    logger.info('Forwarder service stopped');
  }
}

// Graceful shutdown
const service = new ForwarderService();

const gracefulShutdown = async () => {
  logger.info('Shutting down gracefully...');
  await service.stop();
  process.exit(0);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// Start service
service.start().catch((error) => {
  logger.error('Fatal error', { error });
  process.exit(1);
});

// Made with Bob
