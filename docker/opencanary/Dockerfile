# =========================================================
#  OpenCanary Sender Dynamic - Dockerfile
#  Supports TCP/UDP, Offline Queue, and AbuseIPDB Enrichment
# =========================================================

FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    CONFIG_PATH=/etc/opencanary_sender/config.conf \
    LOG_DIR=/var/log/honeypod

# Create required directories
RUN mkdir -p /opt/opencanary_sender /etc/opencanary_sender /var/log/honeypod /tmp

# Copy script and config
COPY opencanary_sender_dynamic.py /opt/opencanary_sender/
COPY config.conf /etc/opencanary_sender/config.conf

# Install dependencies
RUN pip install --no-cache-dir watchdog requests

# Create a non-root user for security
RUN useradd -ms /bin/bash opencanary
USER opencanary

# Set working directory
WORKDIR /opt/opencanary_sender

# Expose default TCP and UDP ports
EXPOSE 12104/tcp
EXPOSE 12105/udp

# Health check - verifies process is running
HEALTHCHECK --interval=60s --timeout=10s --start-period=20s \
  CMD pgrep -f opencanary_sender_dynamic.py || exit 1

# Run the sender script
ENTRYPOINT ["python3", "/opt/opencanary_sender/opencanary_sender_dynamic.py"]
