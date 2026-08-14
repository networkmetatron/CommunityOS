CommunityOS Maps data directory
================================

Place map tile archives here:

  *.pmtiles
  *.mbtiles

Martin serves every supported file found in this directory.

After adding or replacing files:

  sudo communityos app restart maps

Then open:

  https://maps.community.home.arpa


Obtaining map data
------------------

CommunityOS does not ship map datasets (they are large). When Maps is installed,
the pinned `pmtiles` CLI is available at:

  /opt/communityos/bin/pmtiles

Examples:

1) Inspect a remote or local archive

  /opt/communityos/bin/pmtiles show /path/to/file.pmtiles
  /opt/communityos/bin/pmtiles show https://example.com/map.pmtiles

2) Convert MBTiles → PMTiles

  /opt/communityos/bin/pmtiles convert region.mbtiles region.pmtiles
  sudo mv region.pmtiles /opt/communityos/data/maps/
  sudo communityos app restart maps

3) Copy an existing PMTiles file into this directory

  sudo cp ~/Downloads/my-map.pmtiles /opt/communityos/data/maps/
  sudo communityos app restart maps

Public basemap sources (examples; choose what fits your community):

  - Protomaps builds / extracts (see https://protomaps.com and docs)
  - Self-built tiles with tippecanoe, then `pmtiles convert` if needed

Do not delete this README; it is safe to leave alongside your map files.

Downloading regions (CommunityOS)
---------------------------------
Web UI:  https://maps.community.home.arpa  →  Download tab

CLI:
  sudo communityos maps download --preset los-angeles
  sudo communityos maps download --name arizona --bbox -115,31,-109,37 --maxzoom 12
  sudo communityos maps datasets

Internet is required for the initial extract only. Afterward tiles are local.


Protomaps source URL (region downloads)
---------------------------------------
Configured by PMTILES_SOURCE_URL (highest priority in /opt/communityos/.env),
or /opt/communityos/config/maps-source.env.

Default pin for this CommunityOS release:
  https://build.protomaps.com/20260807.pmtiles

To use a newer daily build, edit that URL and restart Maps:
  sudo communityos app restart maps
