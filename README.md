# telemetry

tools-telemetry :: http://github.com/rock-core/tools-telemetry

## DESCRIPTION:

Ruby packages for collecting data from orocos tasks and sending them to a
control station. The package multiplexes data from a set of ports, marshals
them using Typelib and sends them through a TCP link to a demarshaller. The
demarshaller then re-creates ports that map the source ports and outputs
the data on them.

## LICENSE:

LGPLv2 or later

