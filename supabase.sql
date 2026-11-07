-- Execute no SQL Editor do Supabase.
-- O estado da lista só pode ser lido ou alterado pelo usuário dono da linha.

create table if not exists public.lista_compras_estado (
  user_id uuid primary key references auth.users (id) on delete cascade,
  marcados text[] not null default array[]::text[],
  extras jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.lista_compras_estado enable row level security;

grant select, insert, update
  on table public.lista_compras_estado
  to authenticated;

drop policy if exists lista_compras_estado_select_own
  on public.lista_compras_estado;
create policy lista_compras_estado_select_own
  on public.lista_compras_estado
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists lista_compras_estado_insert_own
  on public.lista_compras_estado;
create policy lista_compras_estado_insert_own
  on public.lista_compras_estado
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists lista_compras_estado_update_own
  on public.lista_compras_estado;
create policy lista_compras_estado_update_own
  on public.lista_compras_estado
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);