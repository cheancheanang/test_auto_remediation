# Stage 1: Build the Next.js application
FROM node:22-alpine AS frontend-build

# Set the working directory
WORKDIR /app/frontend

COPY frontend/package.json frontend/package-lock.json ./
COPY frontend/.npmrc .npmrc

# RUN npm ci

# RUN npm ls @babel/runtime

# Install dependencies.
RUN npm install

# Copy the rest of the application code.
COPY frontend/. .

# Build the Next.js application.
RUN npm run build 

# # Ensure the build/static folder exists and copy static files there
RUN cp -r public build/standalone/ && cp -r build/static build/standalone/build/

# # Remove those unused
RUN rm -r public 
RUN rm -r build/cache
RUN rm -r build/server
RUN rm -r build/static

# Stage 2: Final Image with both applications
FROM python:3.11-slim

WORKDIR /app

# Install node.js (required for Next.js)
RUN apt-get update && apt-get install -y curl && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y linux-libc-dev=6.1.140-1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install ODBC libraries (for SQL Server or other databases)
RUN apt-get update && apt-get install g++ gpg unixodbc unixodbc-dev curl lsb-release -y --no-install-recommends  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/apt/keyrings \
    # Add Microsoft key to keyring
    && curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-prod.gpg \
    # Download appropriate package for the OS version (currently Debian 12)
    && curl -sSL https://packages.microsoft.com/config/debian/12/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    # Install ODBC Driver 18 for SQL Server (does not include SQLCMD)
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && rm -rf /var/lib/apt/lists/*

# Create a new non-root user and group
RUN groupadd -r appgroup && useradd -r -g appgroup -m appuser

COPY --from=frontend-build /app/frontend /app/frontend

WORKDIR /app/backend

# Copy requirements and install dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the source code
COPY backend/src ./src

# Copy the .env file to the root of the app directory
COPY frontend/.env /app/frontend/.env
COPY backend/.env /app/backend/.env

RUN chown -R appuser:appgroup /app

# Switch to the non-root user
USER appuser

# Expose the port
EXPOSE 3000

# Set the environment variable for the app environment
ENV ENV=dev

# # Command to run the application
CMD ["sh", "-c", "uvicorn src.main:app --host 0.0.0.0 --port 8000 & cd /app/frontend && node build/standalone/server.js"]
