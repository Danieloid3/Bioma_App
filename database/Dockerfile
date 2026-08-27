FROM postgres:16-bookworm

COPY . /migrations
CMD ["sh", "/migrations/run-migrations.sh"]
