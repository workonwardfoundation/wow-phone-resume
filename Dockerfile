# Use the official Node.js runtime as base image
# Node 20 as specified in package.json engines
FROM node:20-alpine

# Set working directory in container
WORKDIR /app

# Copy package files first for better caching
COPY package*.json ./
COPY tsconfig.json ./
COPY .swcrc* ./

# Install ALL dependencies (including dev dependencies needed for build)
RUN npm ci

# Copy source code
COPY src ./src
COPY scripts ./scripts

# Build the application
RUN npm run build

# Remove dev dependencies and source files to reduce image size
RUN npm prune --omit=dev && \
    rm -rf src scripts tsconfig.json .swcrc*

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

# Change ownership of the app directory
RUN chown -R nextjs:nodejs /app
USER nextjs

# Expose the port that Cloud Run will use
EXPOSE 8080

# Set production environment
ENV NODE_ENV=production

# Health check for Cloud Run
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/api/v1/health', (res) => process.exit(res.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

# Start the server
CMD ["npm", "start"]
