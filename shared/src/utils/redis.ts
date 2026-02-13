import Redis from 'ioredis';
import { logger } from './logger';
import { QueueMessage } from '../types';

function getRedisConfig() {
  return {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379'),
    password: process.env.REDIS_PASSWORD || undefined,
    retryStrategy: (times: number) => {
      const delay = Math.min(times * 50, 2000);
      return delay;
    },
  };
}

export class RedisQueue {
  private client: Redis | null = null;
  private subscriber: Redis | null = null;

  private ensureConnected() {
    if (!this.client) {
      const config = getRedisConfig();
      this.client = new Redis(config);
      this.subscriber = new Redis(config);

      this.client.on('error', (err) => {
        logger.error('Redis client error', { error: err });
      });

      this.subscriber.on('error', (err) => {
        logger.error('Redis subscriber error', { error: err });
      });
    }
  }

  async enqueue(queue: string, message: QueueMessage): Promise<void> {
    this.ensureConnected();
    try {
      await this.client!.lpush(queue, JSON.stringify(message));
      logger.info(`Enqueued message to ${queue}`, { eventId: message.eventId });
    } catch (error) {
      logger.error('Failed to enqueue message', { error, queue });
      throw error;
    }
  }

  async dequeue(queue: string, timeout: number = 0): Promise<QueueMessage | null> {
    this.ensureConnected();
    try {
      const result = await this.client!.brpop(queue, timeout);
      if (!result) return null;

      const [, message] = result;
      return JSON.parse(message);
    } catch (error) {
      logger.error('Failed to dequeue message', { error, queue });
      throw error;
    }
  }

  async scheduleRetry(message: QueueMessage, delaySeconds: number): Promise<void> {
    this.ensureConnected();
    try {
      const score = Date.now() + delaySeconds * 1000;
      await this.client!.zadd('retry_queue', score, JSON.stringify(message));
      logger.info(`Scheduled retry for event ${message.eventId} in ${delaySeconds}s`);
    } catch (error) {
      logger.error('Failed to schedule retry', { error, eventId: message.eventId });
      throw error;
    }
  }

  async getRetryMessages(): Promise<QueueMessage[]> {
    this.ensureConnected();
    try {
      const now = Date.now();
      const messages = await this.client!.zrangebyscore('retry_queue', 0, now);
      
      if (messages.length > 0) {
        await this.client!.zremrangebyscore('retry_queue', 0, now);
      }

      return messages.map(msg => JSON.parse(msg));
    } catch (error) {
      logger.error('Failed to get retry messages', { error });
      throw error;
    }
  }

  async publish(channel: string, message: any): Promise<void> {
    this.ensureConnected();
    try {
      await this.client!.publish(channel, JSON.stringify(message));
    } catch (error) {
      logger.error('Failed to publish message', { error, channel });
      throw error;
    }
  }

  async subscribe(channel: string, callback: (message: any) => void): Promise<void> {
    this.ensureConnected();
    try {
      await this.subscriber!.subscribe(channel);
      this.subscriber!.on('message', (ch, msg) => {
        if (ch === channel) {
          callback(JSON.parse(msg));
        }
      });
    } catch (error) {
      logger.error('Failed to subscribe to channel', { error, channel });
      throw error;
    }
  }

  async disconnect(): Promise<void> {
    if (this.client) {
      await this.client.quit();
    }
    if (this.subscriber) {
      await this.subscriber.quit();
    }
  }
}

export const redisQueue = new RedisQueue();

// Made with Bob
