FROM elixir:1.16-alpine

# Install dependencies
RUN apk add --no-cache \
    nodejs \
    npm \
    git \
    build-base \
    postgresql-client \
    inotify-tools

# Set working directory
WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get

# Copy application code
COPY . .

# Compile the application
RUN mix compile

# Expose port
EXPOSE 4000

# Start the application
CMD ["mix", "phx.server"]