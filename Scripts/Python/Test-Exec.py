import datetime
import platform

print("COOPER Workbench Python execution check -- OK")
print("Timestamp :", datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
print("Host      :", platform.node())
