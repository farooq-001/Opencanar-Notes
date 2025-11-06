#!/usr/bin/env python3
# =====================================================
#  OpenCanary Sender - Dynamic TCP/UDP with Offline Queue
# =====================================================
import os
import json
import time
import socket
import queue
import logging
import platform
import shelve
import configparser
import threading
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import requests

# =====================================================
# CONFIGURATION
# =====================================================
CONFIG_PATH = "/etc/opencanary_sender/config.conf"

def load_config():
    config = configparser.ConfigParser()
    config.read(CONFIG_PATH)
    return config

config = load_config()

# -------- General --------
LOG_DIR = config.get("general", "log_dir", fallback="/var/log/honeypod")
HOSTNAME = platform.node() if config.get("general", "hostname", "auto") == "auto" else config.get("general", "hostname")
VERBOSE = config.getboolean("general", "verbose", fallback=True)
SEND_RATE_LIMIT = config.getint("general", "send_rate_limit", fallback=100)

# -------- Network --------
PROTOCOL = config.get("network", "protocol", fallback="TCP").upper()
TCP_HOST = config.get("network", "tcp_host", fallback="127.0.0.1")
TCP_PORT = config.getint("network", "tcp_port", fallback=12104)
UDP_HOST = config.get("network", "udp_host", fallback="127.0.0.1")
UDP_PORT = config.getint("network", "udp_port", fallback=12105)
OFFLINE_QUEUE_PATH = config.get("network", "offline_queue_path", fallback="/tmp/opencanary_offline.db")

# -------- Database --------
REGISTRY_DB_PATH = config.get("database", "registry_db_path", fallback="/tmp/opencanary_event_registry.db")
CACHE_PATH = config.get("database", "cache_path", fallback="/tmp/abuseipdb_cache.db")

# -------- AbuseIPDB --------
ABUSEIPDB_ENABLED = config.getboolean("abuseipdb", "enabled", fallback=False)
ABUSEIPDB_API_KEY = config.get("abuseipdb", "api_key", fallback="")
ABUSEIPDB_URL = config.get("abuseipdb", "api_url", fallback="https://api.abuseipdb.com/api/v2/check")
ABUSEIPDB_MAX_CACHE_TIME = config.getint("abuseipdb", "max_cache_time", fallback=86400)

# -------- Logging --------
LOG_FILE = config.get("logging", "log_file", fallback="/tmp/opencanary_sender_dynamic.log")
LOG_LEVEL = config.get("logging", "log_level", fallback="INFO").upper()

# =====================================================
# LOGGING SETUP
# =====================================================
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("opencanary_sender")

# =====================================================
# GLOBALS
# =====================================================
event_queue = queue.Queue(maxsize=10000)
stop_event = threading.Event()
lock = threading.Lock()

registry = shelve.open(REGISTRY_DB_PATH, writeback=True)
if "sent" not in registry:
    registry["sent"] = set()

offline_store = shelve.open(OFFLINE_QUEUE_PATH, writeback=True)
if "queue" not in offline_store:
    offline_store["queue"] = []

ip_cache = shelve.open(CACHE_PATH, writeback=True)
if "cache" not in ip_cache:
    ip_cache["cache"] = {}

# =====================================================
# HELPER FUNCTIONS
# =====================================================
def get_event_id(line):
    """Unique hash for deduplication."""
    return hash(line)

def check_abuse_ip(ip):
    """AbuseIPDB lookup with cache support."""
    if not ABUSEIPDB_ENABLED or not ip or ip in ("127.0.0.1", "localhost"):
        return "neutral"

    now = time.time()
    cache = ip_cache["cache"]
    if ip in cache and now - cache[ip]["ts"] < ABUSEIPDB_MAX_CACHE_TIME:
        return cache[ip]["msg"]

    try:
        headers = {"Key": ABUSEIPDB_API_KEY, "Accept": "application/json"}
        r = requests.get(ABUSEIPDB_URL, headers=headers, params={"ipAddress": ip}, timeout=5)
        if r.status_code == 200:
            data = r.json().get("data", {})
            score = data.get("abuseConfidenceScore", 0)
            country = data.get("countryCode", "N/A")
            msg = f"High Risk {score}% ({country})" if score > 50 else "Low Risk" if score > 0 else "neutral"
        else:
            msg = "neutral"
    except Exception as e:
        logger.debug(f"AbuseIPDB failed for {ip}: {e}")
        msg = "neutral"

    cache[ip] = {"msg": msg, "ts": now}
    ip_cache["cache"] = cache
    ip_cache.sync()
    return msg

def save_offline_event(event):
    """Save failed TCP event to offline queue."""
    if PROTOCOL == "UDP":
        return
    with lock:
        q = offline_store["queue"]
        q.append(event)
        offline_store["queue"] = q
        offline_store.sync()

def resend_offline(sock):
    """Resend any stored events once connected."""
    with lock:
        q = offline_store["queue"]
        if not q:
            return
        logger.info(f"Resending {len(q)} offline events...")
        for ev in q[:]:
            try:
                sock.sendall((ev + "\n").encode())
                q.remove(ev)
            except Exception as e:
                logger.error(f"Offline resend failed: {e}")
                break
        offline_store["queue"] = q
        offline_store.sync()

# =====================================================
# EVENT HANDLING
# =====================================================
def classify_event(event):
    """Add metadata, timestamps, and enrich event."""
    event["@timestamp"] = datetime.utcnow().isoformat() + "Z"
    event["host"] = {"name": HOSTNAME}
    src = event.get("src_host", "unknown")
    dst = event.get("dst_host", "unknown")
    event["source.threat"] = check_abuse_ip(src)
    event["destination.threat"] = check_abuse_ip(dst)

    # Generic message generator for all modules
    module = event.get("node_id", "opencanary").split("-")[-1]
    event["tags"] = [module, "opencanary"]
    logtype = event.get("logtype", "")
    message = f"[{module.upper()}] event {logtype} from {src}"
    event["message"] = message
    return event

# =====================================================
# FILE PROCESSING
# =====================================================
file_offsets = {}

def process_line(filepath, line):
    """Process each new log line."""
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        return

    eid = get_event_id(line)
    with lock:
        if eid in registry["sent"]:
            return
        registry["sent"].add(eid)
        registry.sync()

    event = classify_event(event)
    event_json = json.dumps(event, separators=(",", ":"))
    try:
        event_queue.put_nowait(event_json)
    except queue.Full:
        logger.warning("Queue full, dropping event")

def process_new_lines(path):
    """Tail new log lines."""
    last_pos = file_offsets.get(path, 0)
    try:
        with open(path, "r") as f:
            f.seek(last_pos)
            for line in f:
                line = line.strip()
                if line:
                    process_line(path, line)
            file_offsets[path] = f.tell()
    except Exception as e:
        logger.error(f"Error reading {path}: {e}")

class LogHandler(FileSystemEventHandler):
    def on_modified(self, event):
        if not event.is_directory and event.src_path.endswith(".log"):
            process_new_lines(event.src_path)

# =====================================================
# SENDER THREAD
# =====================================================
def sender_thread_func():
    """Handles both TCP and UDP sending."""
    sock = None
    udp_sock = None

    if PROTOCOL == "UDP":
        udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        logger.info(f"UDP Mode active: {UDP_HOST}:{UDP_PORT}")
    else:
        logger.info(f"TCP Mode active: {TCP_HOST}:{TCP_PORT}")

    while not stop_event.is_set():
        try:
            event_json = event_queue.get(timeout=2)

            if PROTOCOL == "UDP":
                try:
                    udp_sock.sendto((event_json + "\n").encode(), (UDP_HOST, UDP_PORT))
                except Exception as e:
                    logger.error(f"UDP send failed: {e}")
                continue

            # TCP mode
            if not sock:
                try:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.connect((TCP_HOST, TCP_PORT))
                    logger.info("TCP connected successfully")
                    resend_offline(sock)
                except Exception as e:
                    logger.error(f"TCP connect failed: {e}")
                    time.sleep(5)
                    continue

            try:
                sock.sendall((event_json + "\n").encode())
                time.sleep(1 / SEND_RATE_LIMIT)
            except Exception as e:
                logger.error(f"TCP send failed: {e}, saving offline")
                save_offline_event(event_json)
                if sock:
                    sock.close()
                    sock = None
                    time.sleep(3)

        except queue.Empty:
            continue
        except Exception as e:
            logger.error(f"Sender thread error: {e}")
            time.sleep(2)

    if sock:
        sock.close()
    if udp_sock:
        udp_sock.close()

# =====================================================
# MAIN LOOP
# =====================================================
def watch_logs(directory):
    """Watch log directory and start sender."""
    observer = Observer()
    handler = LogHandler()
    observer.schedule(handler, directory, recursive=True)
    observer.start()
    logger.info(f"Watching directory: {directory}")

    sender_thread = threading.Thread(target=sender_thread_func, daemon=True)
    sender_thread.start()

    try:
        while not stop_event.is_set():
            time.sleep(2)
    except KeyboardInterrupt:
        logger.info("Stopping OpenCanary sender...")
        stop_event.set()

    observer.stop()
    observer.join()
    registry.close()
    ip_cache.close()
    offline_store.close()

# =====================================================
if __name__ == "__main__":
    watch_logs(LOG_DIR)
