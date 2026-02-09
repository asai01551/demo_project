import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { createServiceLogger, connectDatabase } from 'shared';
import logsRouter from './routes/logs';
import healthRouter from './routes/health';

dotenv.config();

const app = express();
const PORT = process.env.LOGGER_PORT || 3002;
const logger = createServiceLogger('logger-service');

// Security middleware
app.use(helmet());
app.use(cors());

// Body parsing
app.use(express.json());

// Request logging
app.use((req, res, next) => {
  logger.info('Incoming request', {
    method: req.method,
    path: req.path,
  });
  next();
});

// Routes
app.use('/health', healthRouter);
app.use('/logs', logsRouter);

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Error handler
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  logger.error('Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'Internal server error' });
});

// Graceful shutdown
const gracefulShutdown = async () => {
  logger.info('Shutting down gracefully...');
  
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });

  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// Start server
const server = app.listen(PORT, async () => {
  try {
    await connectDatabase();
    logger.info(`Logger service listening on port ${PORT}`);
  } catch (error) {
    logger.error('Failed to start service', { error });
    process.exit(1);
  }
});

export default app;

// Made with Bob
