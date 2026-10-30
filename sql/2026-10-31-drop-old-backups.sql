-- Run once in the Supabase SQL editor (Bashar). Security finding SEC-017.
-- Removes two leftover backup copies made on 27/09/2026 before the intake-batches fix.
-- They are not used by the program and cannot be reached from the app (RLS on, no policies).
drop table if exists public._backup_20260927_intake_batches;
drop table if exists public._backup_20260927_piece_batches;
