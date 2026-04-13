# Inventory Dashboard Business Requirements

This document defines 10 business requirements for the Grafana inventory dashboards provisioned in this repo.

Scope:

- `Inventory Executive Summary`
- `Inventory Stock Monitoring`
- `Inventory Movement & Replenishment`
- `Inventory Aging & Warehouse Performance`

These requirements are written to match the current dashboard implementation and the current mart model in `inventory_mart.*`.

## BR-01: Provide a current inventory position at a glance

### Business need

Business users need to know the current stock position immediately without running ad hoc queries.

### Primary users

- Inventory manager
- Warehouse manager
- Senior management

### Required measures

- latest snapshot date
- on-hand quantity
- available quantity
- inventory value

### Dashboard mapping

- `Inventory Executive Summary`
- panels:
  - `Latest Snapshot Date`
  - `On-hand Quantity`
  - `Available Quantity`
  - `Inventory Value`

### Acceptance criteria

- Users can see the latest available inventory snapshot date.
- Users can distinguish physical stock (`on_hand_qty`) from usable stock (`available_qty`).
- Users can see total inventory value without leaving the dashboard.

## BR-02: Detect low-stock and stockout risk early

### Business need

Operations teams need a clear signal of which SKUs are at risk of stockout so they can replenish before service levels are impacted.

### Primary users

- Inventory planner
- Warehouse operations team
- Procurement team

### Required measures

- low-stock SKU count
- items below reorder point
- low-stock items by warehouse
- zero stock with recent demand

### Dashboard mapping

- `Inventory Executive Summary`
- `Inventory Stock Monitoring`
- panels:
  - `Low-stock SKUs`
  - `Items Below Reorder Point`
  - `Low-stock Items by Warehouse`
  - `Zero Stock with Recent Demand (30 days)`
  - `Top Low-stock Items`

### Acceptance criteria

- Users can identify both the number of affected SKUs and where the problem is concentrated.
- Users can see which zero-stock items still have recent demand.
- Users can drill into warehouse + SKU combinations that require action.

## BR-03: Detect overstock and excess working capital

### Business need

The business needs visibility into excess stock that ties up capital, increases carrying cost, and may lead to obsolescence.

### Primary users

- Inventory manager
- Finance team
- Supply chain manager

### Required measures

- overstock SKU count
- largest overstock positions
- top overstock items

### Dashboard mapping

- `Inventory Executive Summary`
- `Inventory Stock Monitoring`
- panels:
  - `Overstock SKUs`
  - `Largest Overstock Positions`
  - `Top Overstock Items`

### Acceptance criteria

- Users can identify which SKUs exceed `max_stock`.
- Users can see the warehouses and items driving the largest overstock exposure.
- Dashboard supports actions such as markdown, transfer, or purchase suppression.

## BR-04: Track inventory value and its trend over time

### Business need

Management and finance need to understand not only current inventory value, but how it changes over time and where value is concentrated.

### Primary users

- Finance
- Senior management
- Supply chain leadership

### Required measures

- total inventory value
- inventory value trend
- inventory value by warehouse
- inventory value by category

### Dashboard mapping

- `Inventory Executive Summary`
- `Inventory Aging & Warehouse Performance`
- panels:
  - `Inventory Value`
  - `Inventory Value Over Time`
  - `Inventory Value by Warehouse`
  - `Inventory Value by Category`
  - `Latest Inventory Value by Warehouse`

### Acceptance criteria

- Users can see total inventory value for the latest snapshot.
- Users can see whether value is trending up or down.
- Users can identify which warehouses and categories concentrate the most value.

## BR-05: Monitor warehouse-level performance and exception concentration

### Business need

The business needs to compare warehouses to identify where stock, value, and counting performance differ.

### Primary users

- Warehouse manager
- Operations manager
- Supply chain manager

### Required measures

- inventory value by warehouse
- low-stock by warehouse
- inventory accuracy by warehouse
- count variance by warehouse

### Dashboard mapping

- `Inventory Executive Summary`
- `Inventory Stock Monitoring`
- `Inventory Aging & Warehouse Performance`
- panels:
  - `Inventory Value by Warehouse`
  - `Low-stock Items by Warehouse`
  - `Inventory Accuracy by Warehouse`
  - `Count Variance by Warehouse`

### Acceptance criteria

- Users can compare warehouses on both stock exposure and operational quality.
- Warehouses with recurring exceptions are clearly visible.
- Warehouse-level drilldown is possible through table views.

## BR-06: Monitor inventory movement and balance between inbound and outbound flow

### Business need

Operations and management need to know whether stock is flowing in and out in a healthy way, and whether inbound supply is keeping up with outbound demand.

### Primary users

- Warehouse operations
- Supply chain manager
- Senior management

### Required measures

- inbound quantity trend
- outbound quantity trend
- receiving vs dispatch by warehouse
- top moving SKUs

### Dashboard mapping

- `Inventory Executive Summary`
- `Inventory Movement & Replenishment`
- panels:
  - `Inbound vs Outbound Trend (90 days)`
  - `Inbound vs Outbound (90 days)`
  - `Receiving vs Dispatch by Warehouse (30 days)`
  - `Top Moving SKUs (30 days)`

### Acceptance criteria

- Users can compare inbound and outbound movement over time.
- Users can identify which warehouses are net receivers or net dispatchers.
- Users can identify fast-moving items that drive operational load.

## BR-07: Support replenishment planning and open PO management

### Business need

Procurement and planning teams need a practical view of replenishment demand, purchase orders already in flight, and suggested reorder quantities.

### Primary users

- Procurement
- Inventory planner
- Supply chain manager

### Required measures

- open PO quantity
- open PO lines
- items below reorder point
- suggested reorder quantity
- replenishment recommendation
- PO open vs received trend

### Dashboard mapping

- `Inventory Movement & Replenishment`
- panels:
  - `Open PO Quantity`
  - `Open PO Lines`
  - `Items Below Reorder Point`
  - `Suggested Reorder Qty`
  - `Replenishment Recommendation`
  - `PO Open vs Received Trend`

### Acceptance criteria

- Users can distinguish demand for replenishment from supply already on order.
- Users can identify where open POs are not yet closing the gap.
- Dashboard provides a practical reorder suggestion for action prioritization.

## BR-08: Identify slow-moving and dead stock for working-capital optimization

### Business need

The business needs visibility into stock that is not moving, so it can reduce dead inventory, improve cash efficiency, and avoid obsolescence.

### Primary users

- Finance
- Inventory manager
- Category manager

### Required measures

- dead stock value
- slow-moving value
- aging value by bucket
- top dead / slow-moving SKUs
- slow-moving SKUs with no movement in 30 days

### Dashboard mapping

- `Inventory Movement & Replenishment`
- `Inventory Aging & Warehouse Performance`
- panels:
  - `Slow-moving SKUs (no movement in 30 days)`
  - `Dead Stock Value (90+ days)`
  - `Slow-moving Value (31-90 days)`
  - `Aging Value by Bucket`
  - `Top Dead / Slow-moving SKUs`

### Acceptance criteria

- Users can distinguish short-term slow-moving stock from longer-term dead stock.
- Users can quantify value at risk, not just unit counts.
- Users can identify specific SKUs requiring liquidation, transfer, or policy review.

## BR-09: Measure inventory count quality using accuracy and variance

### Business need

The business needs to know whether inventory records are trustworthy enough to support planning, execution, and finance reporting.

### Primary users

- Warehouse manager
- Internal control / audit
- Finance

### Required measures

- inventory accuracy percentage
- average absolute count variance
- count variance trend
- count variance by warehouse

### Dashboard mapping

- `Inventory Aging & Warehouse Performance`
- panels:
  - `Inventory Accuracy % (60 days)`
  - `Avg Absolute Count Variance`
  - `Count Variance Trend (60 days)`
  - `Inventory Accuracy by Warehouse`
  - `Count Variance by Warehouse`

### Acceptance criteria

- Users can see both exact-match count quality and mismatch magnitude.
- Dashboard makes it clear that `accuracy` and `variance` are different signals.
- Users can identify which warehouses have persistent count-quality issues.

## BR-10: Monitor data freshness and reporting reliability

### Business need

Users need confidence that the dashboard reflects recent data and that key master-data fields are complete enough for decision-making.

### Primary users

- BI/report owners
- Operations managers
- Technical support / data engineering

### Required measures

- latest snapshot date
- snapshot lag in hours
- last mart ingestion time
- negative stock rows
- data quality summary

### Dashboard mapping

- `Inventory Executive Summary`
- `Inventory Aging & Warehouse Performance`
- panels:
  - `Latest Snapshot Date`
  - `Snapshot Lag (hours)`
  - `Last Mart Ingestion Time`
  - `Negative Stock Rows (Latest)`
  - `Data Quality Summary (Latest Snapshot)`

### Acceptance criteria

- Users can tell whether dashboard data is fresh enough to trust operationally.
- Users can quickly identify key data quality exceptions.
- Dashboard supports escalation when mart refresh or ingestion appears stale.

## Requirement-to-dashboard summary

| Requirement | Executive Summary | Stock Monitoring | Movement & Replenishment | Aging & Warehouse Performance |
| --- | --- | --- | --- | --- |
| BR-01 Current inventory position | Yes | Partial | No | Partial |
| BR-02 Low-stock and stockout risk | Yes | Yes | Partial | No |
| BR-03 Overstock exposure | Yes | Yes | No | No |
| BR-04 Inventory value and trend | Yes | No | No | Yes |
| BR-05 Warehouse-level comparison | Yes | Yes | Partial | Yes |
| BR-06 Inbound/outbound flow | Yes | No | Yes | No |
| BR-07 Replenishment and PO management | No | Partial | Yes | No |
| BR-08 Slow-moving and dead stock | No | Partial | Yes | Yes |
| BR-09 Count quality and variance | No | No | No | Yes |
| BR-10 Data freshness and reliability | Partial | No | No | Yes |

## Notes

- These are business requirements, not technical implementation requirements.
- Some panels satisfy more than one requirement.
- Some requirements currently rely on simplified demo logic:
  - supplier SLA is a proxy, not true on-time PO performance
  - aging and dead-stock metrics depend on enough historical movement depth

For metric definitions and field meaning, see [DASHBOARD_FIELD_GLOSSARY.md](/Users/huynhthanhdat/Workspace/source-ingestion-demo/grafana/DASHBOARD_FIELD_GLOSSARY.md).
