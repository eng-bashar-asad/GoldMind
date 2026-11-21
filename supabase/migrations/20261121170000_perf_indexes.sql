-- Speed (بشار 2026-11-21): composite indexes for the lists every page reads «this store, newest first»,
-- pieces by store + status, and covering indexes for the 14 foreign keys the advisor flagged.
create index if not exists daily_cash_log_store_created_idx   on public.daily_cash_log   (store_id, created_at desc);
create index if not exists trader_movements_store_created_idx on public.trader_movements (store_id, created_at desc);
create index if not exists trader_movements_trader_created_idx on public.trader_movements (trader_id, created_at);
create index if not exists customer_debts_store_created_idx   on public.customer_debts   (store_id, created_at desc);
create index if not exists customer_debts_customer_created_idx on public.customer_debts  (customer_id, created_at);
create index if not exists invoices_store_created_idx         on public.invoices         (store_id, created_at desc);
create index if not exists cash_movements_store_created_idx   on public.cash_movements   (store_id, created_at desc);
create index if not exists audit_log_store_created_idx        on public.audit_log        (store_id, created_at desc);
create index if not exists pieces_store_status_idx            on public.pieces           (store_id, status);
create index if not exists branch_transfer_items_diamond_piece_id_idx on public.branch_transfer_items (diamond_piece_id);
create index if not exists branch_transfer_items_piece_id_idx         on public.branch_transfer_items (piece_id);
create index if not exists branch_transfer_items_received_by_idx      on public.branch_transfer_items (received_by);
create index if not exists branch_transfers_created_by_idx            on public.branch_transfers (created_by);
create index if not exists branch_transfers_organization_id_idx       on public.branch_transfers (organization_id);
create index if not exists branch_transfers_received_by_idx           on public.branch_transfers (received_by);
create index if not exists invoices_salesperson_id_idx                on public.invoices (salesperson_id);
create index if not exists organizations_head_office_store_id_idx     on public.organizations (head_office_store_id);
create index if not exists piece_barcode_history_changed_by_idx       on public.piece_barcode_history (changed_by);
create index if not exists piece_barcode_history_piece_id_idx         on public.piece_barcode_history (piece_id);
create index if not exists piece_chip_history_changed_by_idx          on public.piece_chip_history (changed_by);
create index if not exists piece_chip_history_piece_id_idx            on public.piece_chip_history (piece_id);
create index if not exists pieces_reserved_customer_id_idx            on public.pieces (reserved_customer_id);
create index if not exists trader_scrap_draws_lot_id_idx              on public.trader_scrap_draws (lot_id);
