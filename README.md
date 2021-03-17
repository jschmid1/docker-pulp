# Pulp Docker images

Pulp installation consists of 4 containers:

- pulp-api
- pulp-content
- pulp-resource-manager
- pulp-worker

All of these images are using `pulp-core` as a base image.

## Configuration

To run and configure Pulp, you have 2 options:

1. Export `PULP_SETTINGS` to location with your configuration file and manage
   it as host path of Kubernetes configmap.
   Pulp is using [Dynaconf](https://dynaconf.readthedocs.io/en/latest/guides/examples.html) so you can use various formats.
2. Use environment variables entirely to configure Pulp, we are going to use
   this option.

### Configuration options

- `PULP_SECRET_KEY`

   ```
   import random

   chars = 'abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*(-_=+)'
   print(''.join(random.choice(chars) for i in range(50)))
   ```

- `PULP_DATABASES__default__ENGINE` (defaults to `django.db.backends.postgresql_psycopg2`)
- `PULP_DATABASES__default__USER` (defaults to `pulp`)
- `PULP_DATABASES__default__PASSWORD`
- `PULP_DATABASES__default__NAME` (defaults to `pulp`)
- `PULP_DATABASES__default__HOST`

- `PULP_REDIS_URL` (eg. `redis://redis.pulp.svc.cluster.local:6379/1`)

- `PULP_ADMIN_PASSWORD`

- `CONTENT_ORIGIN` - pointer to content service (eg. `https://pulp.example.com:24816`)
- `CONTENT_PATH_PREFIX` - defaults to `/pulp/content/`

## Installation

### Volumes

You need to provide /var/lib/pulp or at least /var/lib/pulp/artifacts as a
persistent shared volume across all pulp containers.

Don't forget to ensure correct permissions (`chown 995:995`).

If you don't want to use shared volume, use alternative backend to
django-storages, eg. AWS S3 or Azure Blob Storage.

### First run

pulp-api entrypoint will automatically handle database upgrades by running

```
django-admin migrate --noinput
```

However you should set admin password on your own by exec in pulp-api
container and running following command. Or set `PULP_ADMIN_PASSWORD`
variable.

```
django-admin reset-admin-password --password <yoursecretpassword>
```

## Development

To deploy pulp locally for development and testing purposes, use
docker-compose:

```
mkdir -p .volume/pulp && chown 995:995 .volume/pulp
docker-compose up
```

Then you can access Pulp on http://localhost:24817/pulp/api/v3/

## Usage

### upload a static file

Create a repo to hold the content (only needs done once)
```bash
http --auth admin:admin post :24817/pulp/api/v3/repositories/file/file/ name=static
```
```json
{
    "description": null,
    "latest_version_href": "/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/versions/0/",
    "name": "static",
    "pulp_created": "2021-03-16T16:04:35.269473Z",
    "pulp_href": "/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/",
    "pulp_labels": {},
    "remote": null,
    "versions_href": "/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/versions/"
}

```

Upload the content, which creates an artifact with file content:
```bash
http --form --auth admin:admin post :24817/pulp/api/v3/content/file/files/ relative_path=stuff/afile repository=/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/ file@/tmp/file
```
```json
{
    "task": "/pulp/api/v3/tasks/016f7df4-0d02-4c8d-b924-c027d9ecd7fb/"
}
```
```bash
http --auth admin:admin get :24817/pulp/api/v3/tasks/016f7df4-0d02-4c8d-b924-c027d9ecd7fb/
```
```json
{
    "child_tasks": [],
    "created_resources": [
        "/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/versions/1/",
        "/pulp/api/v3/content/file/files/94869ed1-b030-4ab7-a76c-72907118f149/"
    ],
    "error": null,
    "finished_at": "2021-03-17T22:51:49.214574Z",
    "logging_cid": "89e94a55f5764878a60dfe6b05a0b19f",
    "name": "pulpcore.app.tasks.base.general_create",
    "parent_task": null,
    "progress_reports": [],
    "pulp_created": "2021-03-17T22:51:47.866812Z",
    "pulp_href": "/pulp/api/v3/tasks/016f7df4-0d02-4c8d-b924-c027d9ecd7fb/",
    "reserved_resources_record": [
        "/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/",
        "/pulp/api/v3/artifacts/6fc5389b-922b-4a82-9309-4ca1c7c9984a/"
    ],
    "started_at": "2021-03-17T22:51:48.598495Z",
    "state": "completed",
    "task_group": null,
    "worker": "/pulp/api/v3/workers/89f98a70-7ba8-4569-9665-c7246ea8f730/"
}

```

This created a respository resource and a file resource.  The repository is version 1, based on the URL.
Create a publication from that repository version:
```bash
http --auth admin:admin post :24817/pulp/api/v3/publications/file/file/ repository_version=/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/versions/1/
```
```json
{
    "task": "/pulp/api/v3/tasks/5f105a2c-9f79-4879-8382-7887f95a39b3/"
}

```
```bash
http --auth admin:admin get :24817/pulp/api/v3/tasks/5f105a2c-9f79-4879-8382-7887f95a39b3/
```
```json
{
    "child_tasks": [],
    "created_resources": [
        "/pulp/api/v3/publications/file/file/2fc32849-cf23-44c5-8030-b33a1fee2036/"
    ],
    "error": null,
    "finished_at": "2021-03-17T23:04:16.645661Z",
    "logging_cid": "323eef736d9d48d8b4ac4ccf949f8b4c",
    "name": "pulp_file.app.tasks.publishing.publish",
    "parent_task": null,
    "progress_reports": [],
    "pulp_created": "2021-03-17T23:04:14.306739Z",
    "pulp_href": "/pulp/api/v3/tasks/5f105a2c-9f79-4879-8382-7887f95a39b3/",
    "reserved_resources_record": [
        "/pulp/api/v3/repositories/file/file/170ef990-fb50-44c4-b170-c60e0c07549f/"
    ],
    "started_at": "2021-03-17T23:04:15.078704Z",
    "state": "completed",
    "task_group": null,
    "worker": "/pulp/api/v3/workers/89f98a70-7ba8-4569-9665-c7246ea8f730/"
}

```

Finally, create a distribution for that publication:
```bash
http --auth admin:admin post :24817/pulp/api/v3/distributions/file/file/ base_path=static/somepath name=somedist publication=/pulp/api/v3/publications/file/file/2fc32849-cf23-44c5-8030-b33a1fee2036/
```
```json
{
    "task": "/pulp/api/v3/tasks/90fee054-362f-4e3e-b61e-1e510fe9d160/"
}

```
```bash
http --auth admin:admin get :24817/pulp/api/v3/tasks/90fee054-362f-4e3e-b61e-1e510fe9d160/
```
```json
{
    "child_tasks": [],
    "created_resources": [
        "/pulp/api/v3/distributions/file/file/4aee4f8d-1d65-425c-8fbb-aeed970a9fc2/"
    ],
    "error": null,
    "finished_at": "2021-03-17T23:18:41.342422Z",
    "logging_cid": "2b4b675d2b504288ac72d58a4241f82f",
    "name": "pulpcore.app.tasks.base.general_create",
    "parent_task": null,
    "progress_reports": [],
    "pulp_created": "2021-03-17T23:18:40.544524Z",
    "pulp_href": "/pulp/api/v3/tasks/90fee054-362f-4e3e-b61e-1e510fe9d160/",
    "reserved_resources_record": [
        "/api/v3/distributions/"
    ],
    "started_at": "2021-03-17T23:18:41.009381Z",
    "state": "completed",
    "task_group": null,
    "worker": "/pulp/api/v3/workers/89f98a70-7ba8-4569-9665-c7246ea8f730/"
}

```

The file was uploaded with the name `stuff/afile` and the distribution was called `static/somepath`.  Therefore, the file is available at /static/somepath/stuff/afile relative to the content root.  In out helm chart, we set PULP_CONTENT_ROOT to `/`, so it's at http://pulp-server/static/somepath/stuff/afile.  Further, at /static/somepath/PULP_MANIFST, there is a text file which lists each file(s), the checksum (sha256 by default), and the size of the file (comma-separated).

Of note: when you attempt to download that path, you get a redirect to the artifact URL on S3 with `Content-Disposition: attachment;filename=stuff/afile` in the header; the content server doesn't provide it directly.  It only provides the content index and the link.
