# Data Source

## ⚡ Judge Quick Summary
- Total tickets: ~8,600
- Used for embeddings: 5,588
- Missing resolutions auto-generated: 2,819
- Closed tickets with resolutions (context): 2,769

---

## Dataset Information

**Source**: [Kaggle - Customer Support Ticket Dataset](https://www.kaggle.com/datasets/suraj520/customer-support-ticket-dataset)  
**File**: `Data/TicketData_customer_support_tickets.csv`  
**Records**: ~8,600 customer support tickets  

**Why this dataset?**  
Chosen for its *real-world complexity* and *imperfect resolutions*, which highlight the importance of AI combined with data quality awareness.

> **📥 Optional**: You can download the original dataset from [Kaggle](https://www.kaggle.com/datasets/suraj520/customer-support-ticket-dataset) if you want to run this project with fresh data.

---

## Data Schema

| Column | Type | Description |
|--------|------|-------------|
| `ticket_id` | Integer | Unique identifier |
| `subject` | String | Brief issue description |
| `description` | String | Detailed problem description |
| `status` | String | Current status (open, resolved, closed) |
| `priority` | String | Priority level (low, medium, high) |
| `customer_email` | String | Customer email |
| `product_purchased` | String | Product purchased |
| `cust_satisfaction` | Integer | Satisfaction rating (1–5) |

**Additional engineered columns (added during data cleaning):**
- `customer_age`  
- `customer_gender`  
- `first_response_time`  
- `time_to_resolution`  

These were derived to enable **demographic analysis, SLA monitoring, and performance tracking**.

---

## Data Quality Notes

- **Real-world data**: Actual customer support tickets
- **Mixed quality resolutions**:  
  - *Bad*: `"Fast item someone lay because act deal hand"`  
  - *Good*: `"Reset the user’s password and confirm login with MFA enabled"`  
- **Learning opportunity**: Demonstrates the critical role of data quality in AI system success

---

## Usage in Project

- **5,588 tickets** processed with vector embeddings  
- **2,819 open tickets** identified for AI resolution generation  
- **2,769 closed tickets** with existing resolutions used as high-quality RAG context  

---

*Source: Kaggle Dataset - Customer Support Ticket Dataset*  
