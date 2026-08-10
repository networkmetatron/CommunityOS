CommunityOS optional app: Hermes Agent data

This directory is mounted into the Hermes container as /opt/data.
It holds config, sessions, skills, and agent memory.

Model weights are NOT stored here — they live in the shared Ollama volume.
Removing the Hermes app does not delete Ollama models.
