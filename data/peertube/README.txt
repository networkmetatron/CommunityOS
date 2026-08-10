PeerTube (Streaming) data directory
===================================

Login
-----
Username: the CommunityOS administrator username (usually admin)
Password: the CommunityOS administrator password

PeerTube normally creates a fixed account named "root". CommunityOS renames
that account to ADMIN_USER and sets the password from ADMIN_PASS so Streaming
uses the same administrator identity as the rest of the platform.

Manual password reset
---------------------
  sudo docker exec -it -u peertube communityos-peertube \
    npm run reset-password -- -u admin
