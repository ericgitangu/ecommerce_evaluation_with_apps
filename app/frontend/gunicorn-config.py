# Gunicorn configuration
bind = "0.0.0.0:5003"
workers = 1
threads = 2
worker_class = "sync"
worker_connections = 1000
timeout = 120
keepalive = 5
errorlog = "-"
accesslog = "-"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'
loglevel = "info"