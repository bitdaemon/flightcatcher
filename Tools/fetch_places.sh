#!/bin/sh
# Downloads OurAirports airport data (city names, IATA codes) for Tools/cifp_to_package.py.
# Source: https://github.com/davidmegginson/ourairports-data (public domain).
set -e
mkdir -p "$(dirname "$0")/../../Data/places"
curl -sS -o "$(dirname "$0")/../../Data/places/airports.csv" \
  https://raw.githubusercontent.com/davidmegginson/ourairports-data/main/airports.csv
