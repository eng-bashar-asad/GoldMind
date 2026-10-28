-- Overdue-debt alerts are for individual customers only; trader (wholesale) alerts are off by default.
alter table public.stores alter column debt_alert_traders set default false;
update public.stores set debt_alert_traders = false where debt_alert_traders is distinct from false;
