-- Deleting a company from the admin panel (admin_delete_store) failed when the store had HR employees,
-- inventory counts, diamond lots, KYC screenings or RFID jobs: these foreign keys had no ON DELETE CASCADE.
alter table public.inventory_counts drop constraint inventory_counts_store_id_fkey, add constraint inventory_counts_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
alter table public.inventory_count_scans drop constraint inventory_count_scans_store_id_fkey, add constraint inventory_count_scans_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
alter table public.inventory_count_expected drop constraint inventory_count_expected_store_id_fkey, add constraint inventory_count_expected_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
alter table public.diamond_stock_lots drop constraint diamond_stock_lots_store_id_fkey, add constraint diamond_stock_lots_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
alter table public.hr_employees drop constraint hr_employees_store_id_fkey, add constraint hr_employees_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
alter table public.hr_leave_requests drop constraint hr_leave_requests_store_id_fkey, add constraint hr_leave_requests_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
alter table public.kyc_screenings drop constraint kyc_screenings_store_id_fkey, add constraint kyc_screenings_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
alter table public.rfid_write_jobs drop constraint rfid_write_jobs_store_id_fkey, add constraint rfid_write_jobs_store_id_fkey foreign key (store_id) references public.stores(id) on delete cascade;
