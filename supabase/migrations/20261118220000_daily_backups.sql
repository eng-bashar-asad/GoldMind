-- Daily per-company backups (بشار 2026-11-18): every night at 03:00 company time the
-- daily-backup edge function saves one file per company and day in the private bucket
-- «store-backups» (<store_id>/<YYYY-MM-DD>.json.gz). Each day is a new file; old ones are kept.
-- The owner can open any day and bring back one item that was deleted since.

insert into storage.buckets (id, name, public) values ('store-backups', 'store-backups', false)
on conflict (id) do nothing;

-- Everything one company owns, as JSON: every table with a store_id, plus the child tables
-- that hang off them (invoice lines, branch transfers, repair gold lines) and the store row.
create or replace function public.gm_store_snapshot(sid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; out jsonb := '{}'; part jsonb;
begin
  for r in select c.relname from pg_class c
           join pg_attribute a on a.attrelid = c.oid and a.attname = 'store_id' and not a.attisdropped
           where c.relkind = 'r' and c.relnamespace = 'public'::regnamespace
             and c.relname not in ('client_errors')
           order by 1
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I t where t.store_id = $1', r.relname)
      into part using sid;
    out := out || jsonb_build_object(r.relname, part);
  end loop;
  out := out || jsonb_build_object(
    'stores', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from stores s where s.id = sid),
    'invoice_items', (select coalesce(jsonb_agg(to_jsonb(i)), '[]') from invoice_items i
                      where i.invoice_id in (select id from invoices where store_id = sid)),
    'branch_transfers', (select coalesce(jsonb_agg(to_jsonb(b)), '[]') from branch_transfers b
                         where b.from_store_id = sid or b.to_store_id = sid),
    'branch_transfer_items', (select coalesce(jsonb_agg(to_jsonb(i)), '[]') from branch_transfer_items i
                              where i.transfer_id in (select id from branch_transfers where from_store_id = sid or to_store_id = sid)),
    'repair_gold_lines', (select coalesce(jsonb_agg(to_jsonb(l)), '[]') from repair_gold_lines l
                          where l.expense_entry_id in (select id from expense_entries where store_id = sid)));
  return out;
end $$;
revoke all on function public.gm_store_snapshot(uuid) from public, anon, authenticated;
grant execute on function public.gm_store_snapshot(uuid) to service_role;

-- Bring one deleted item back from a backup, with what was deleted together with it:
--  trader movement → the rest of its voucher (same batch) + its cash rows + their daily-box rows
--  customer movement / expense → its cash row + daily-box rows; cash row → its daily-box rows.
-- Only rows that no longer exist are inserted; nothing that exists now is overwritten.
create or replace function public.gm_backup_restore(sid uuid, tbl text, rid uuid, snap jsonb, who uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare main jsonb; rows jsonb := '[]'; r jsonb; n int := 0; present boolean; cash_ids uuid[] := '{}'; ids uuid[] := '{}';
begin
  if tbl not in ('trader_movements', 'customer_debts', 'cash_movements', 'expense_entries', 'customers', 'traders', 'daily_cash_log') then
    raise exception 'هذا النوع لا يُسترجع من هنا';
  end if;
  select e into main from jsonb_array_elements(snap->tbl) e where (e->>'id')::uuid = rid and (e->>'store_id')::uuid = sid;
  if main is null then raise exception 'العنصر غير موجود في هذه النسخة'; end if;

  -- the rows of the main table to bring back (a whole trader voucher comes back together)
  -- (only the rows of it that no longer exist)
  if tbl = 'trader_movements' then
    select coalesce(jsonb_agg(e), '[]') into rows from jsonb_array_elements(snap->'trader_movements') e
     where (e->>'store_id')::uuid = sid
       and ((e->>'id')::uuid = rid or (main->>'batch_id' is not null and e->>'batch_id' = main->>'batch_id'))
       and not exists (select 1 from trader_movements t where t.id = (e->>'id')::uuid);
  else
    execute format('select exists(select 1 from public.%I where id = $1)', tbl) into present using rid;
    if not present then rows := jsonb_build_array(main); end if;
  end if;
  if jsonb_array_length(rows) = 0 then raise exception 'هذا العنصر موجود حالياً — لا حاجة لاسترجاعه'; end if;
  select array_agg((e->>'id')::uuid) into ids from jsonb_array_elements(rows) e;

  -- cash rows that belong to it (they must exist before rows that point at them)
  if tbl = 'trader_movements' then
    select coalesce(array_agg((e->>'id')::uuid), '{}') into cash_ids from jsonb_array_elements(snap->'cash_movements') e
     where (e->>'trader_movement_id')::uuid = any(ids);
  elsif tbl in ('customer_debts', 'expense_entries') and main->>'cash_movement_id' is not null then
    cash_ids := array[(main->>'cash_movement_id')::uuid];
  elsif tbl = 'cash_movements' then
    if main->>'invoice_id' is not null then raise exception 'حركة فاتورة — تُسترجع من الفاتورة نفسها'; end if;
    cash_ids := ids;
  end if;

  if tbl <> 'cash_movements' and tbl <> 'trader_movements' then
    for r in select e from jsonb_array_elements(snap->'cash_movements') e
              where (e->>'id')::uuid = any(cash_ids) and not exists (select 1 from cash_movements c where c.id = (e->>'id')::uuid) loop
      insert into cash_movements select * from jsonb_populate_record(null::cash_movements, r); n := n + 1;
    end loop;
  end if;

  for r in select e from jsonb_array_elements(rows) e loop
    execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)', tbl, tbl) using r;
    n := n + 1;
  end loop;

  if tbl in ('cash_movements', 'trader_movements') then
    for r in select e from jsonb_array_elements(snap->'cash_movements') e
              where (e->>'id')::uuid = any(cash_ids) and not exists (select 1 from cash_movements c where c.id = (e->>'id')::uuid) loop
      insert into cash_movements select * from jsonb_populate_record(null::cash_movements, r); n := n + 1;
    end loop;
  end if;

  for r in select e from jsonb_array_elements(snap->'daily_cash_log') e
            where (e->>'cash_movement_id')::uuid = any(cash_ids)
               or (cash_ids <> '{}' and e->>'link_group' is not null and exists (
                     select 1 from jsonb_array_elements(snap->'daily_cash_log') d
                      where (d->>'cash_movement_id')::uuid = any(cash_ids) and d->>'link_group' = e->>'link_group'))
  loop
    if not exists (select 1 from daily_cash_log l where l.id = (r->>'id')::uuid) then
      insert into daily_cash_log select * from jsonb_populate_record(null::daily_cash_log, r); n := n + 1;
    end if;
  end loop;

  insert into audit_log (store_id, staff_id, action_type, description)
  values (sid, (select id from staff where user_id = who and store_id = sid limit 1), 'backup_restore',
          'استرجاع من نسخة احتياطية: ' || tbl || ' (' || n || ' سطر)');
  return jsonb_build_object('ok', true, 'rows', n);
end $$;
revoke all on function public.gm_backup_restore(uuid, text, uuid, jsonb, uuid) from public, anon, authenticated;
grant execute on function public.gm_backup_restore(uuid, text, uuid, jsonb, uuid) to service_role;

-- The nightly call carries a key kept in the vault; the function checks it here.
create extension if not exists pg_net;
create extension if not exists pg_cron;
create extension if not exists supabase_vault;
select vault.create_secret(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 'backup_cron_key', 'daily-backup cron key')
where not exists (select 1 from vault.secrets where name = 'backup_cron_key');

create or replace function public.gm_backup_key_ok(k text)
returns boolean language sql security definer set search_path = public as $$
  select k is not null and k = (select decrypted_secret from vault.decrypted_secrets where name = 'backup_cron_key');
$$;
revoke all on function public.gm_backup_key_ok(text) from public, anon, authenticated;
grant execute on function public.gm_backup_key_ok(text) to service_role;

-- every hour; the function backs up the companies for which it is now 03:00 (once per day)
select cron.unschedule('gm-daily-backup') where exists (select 1 from cron.job where jobname = 'gm-daily-backup');
select cron.schedule('gm-daily-backup', '5 * * * *', $cron$
  select net.http_post(
    url := 'https://puzkfwbmipldzgwofhjg.supabase.co/functions/v1/daily-backup',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-backup-key', (select decrypted_secret from vault.decrypted_secrets where name = 'backup_cron_key')),
    body := '{"action":"cron"}'::jsonb,
    timeout_milliseconds := 60000);
$cron$);
