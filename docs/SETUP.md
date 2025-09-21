# Setup Guide

## Prerequisites

- Google Cloud Project with BigQuery and Vertex AI APIs enabled
- `gcloud` CLI installed and authenticated
- Project ID: `insightweaver` (replace with your project ID)

## Step 1: Create BigQuery Connection

```bash
bq mk --connection \
  --connection_type=CLOUD_RESOURCE \
  --project_id=insightweaver \
  --location=US \
  hackathon_ai_connection
```

## Step 2: Grant IAM Roles

```bash
# Get the service account
bq show --connection --project_id=insightweaver --location=US hackathon_ai_connection

# Grant roles (replace SERVICE_ACCOUNT_EMAIL with actual email)
gcloud projects add-iam-policy-binding insightweaver \
  --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
  --role="roles/aiplatform.user"

gcloud projects add-iam-policy-binding insightweaver \
  --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
  --role="roles/bigquery.jobUser"
```

## Step 3: Run SQL Scripts

Execute the SQL scripts in order:
1. `01_load_data.sql` - Load data from GCS
2. `02_clean_data.sql` - Clean and normalize data
3. `04_models.sql` - Create AI models
4. `05_generate_embeddings.sql` - Generate vector embeddings
5. `06_vector_index.sql` - Create vector index
6. `07_semantic_search.sql` - Test semantic search
7. `08_gemini_rag.sql` - Test RAG system
8. `10_generate_missing_resolutions.sql` - Generate missing resolutions

## For New Users

Replace `insightweaver` with your project ID in all SQL files.

---

*Setup guide for The Semantic Detective project*
