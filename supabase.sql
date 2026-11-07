-- Execute no SQL Editor do Supabase.
-- O estado da lista só pode ser lido ou alterado pelo usuário dono da linha.

create table if not exists public.lista_compras_catalogo (
  id boolean primary key default true check (id),
  produtos jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.lista_compras_catalogo enable row level security;

grant select on table public.lista_compras_catalogo to authenticated;

drop policy if exists lista_compras_catalogo_read
  on public.lista_compras_catalogo;
create policy lista_compras_catalogo_read
  on public.lista_compras_catalogo
  for select
  to authenticated
  using (true);

insert into public.lista_compras_catalogo (id, produtos)
values (
  true,
  $catalogo$[
    {"categoria":"Mercearia","itens":[{"nome":"Arroz","quantidade":"6 pacotes de 1 kg"},{"nome":"Açúcar","quantidade":"3 kg"},{"nome":"Cuscuz","quantidade":"6 pacotes"},{"nome":"Tapioca","quantidade":"6 pacotes"},{"nome":"Extrato de tomate","quantidade":"2 unidades"},{"nome":"Milho verde","quantidade":"1 lata"},{"nome":"Biscoito Cream Cracker","quantidade":"2 pacotes"},{"nome":"Biscoito","quantidade":"Não informada"},{"nome":"Massa para bolo","quantidade":"3 unidades"},{"nome":"Fermento biológico","quantidade":"1 unidade"},{"nome":"Massa de pastel","quantidade":"Não informada"},{"nome":"Pimenta-do-reino moída","quantidade":"Não informada"},{"nome":"Óleo","quantidade":"Não informada"},{"nome":"Ketchup","quantidade":"1 frasco grande"},{"nome":"Café","quantidade":"5 pacotes"}]},
    {"categoria":"Carnes e frios","itens":[{"nome":"Frango","quantidade":"4 bandejas"},{"nome":"Carne bovina","quantidade":"2 kg"},{"nome":"Carne moída","quantidade":"1 kg"},{"nome":"Carne para hambúrguer","quantidade":"8 unidades"},{"nome":"Mortadela","quantidade":"Não informada"}]},
    {"categoria":"Laticínios","itens":[{"nome":"Creme de leite","quantidade":"2 unidades"},{"nome":"Leite condensado","quantidade":"1 unidade"},{"nome":"Leite em pó","quantidade":"Não informada","observacao":"Sem lactose"},{"nome":"Queijo","quantidade":"Não informada","observacao":"Sem lactose"},{"nome":"Iogurte","quantidade":"Não informada","observacao":"Sem lactose"},{"nome":"Margarina","quantidade":"Não informada"}]},
    {"categoria":"Isabelle","itens":[]},
    {"categoria":"Outros","itens":[{"nome":"Ovos","quantidade":"2 bandejas"},{"nome":"Pão de queijo","quantidade":"Não informada"},{"nome":"Gelatina de maracujá","quantidade":"2 unidades"},{"nome":"Macaxeira","quantidade":"Não informada"},{"nome":"Sachê de ração para gato","quantidade":"Não informada"},{"nome":"Açaí","quantidade":"1 pote"}]},
    {"categoria":"Verduras e legumes","itens":[{"nome":"Alface","quantidade":"Não informada"},{"nome":"Tomate","quantidade":"Não informada"},{"nome":"Cenoura","quantidade":"Não informada"},{"nome":"Beterraba","quantidade":"Não informada"},{"nome":"Pepino","quantidade":"Não informada"},{"nome":"Cebola roxa","quantidade":"Não informada"}]},
    {"categoria":"Frutas e polpas","itens":[{"nome":"Banana","quantidade":"Não informada"},{"nome":"Maçã","quantidade":"Não informada"},{"nome":"Laranja","quantidade":"Não informada"},{"nome":"Tangerina","quantidade":"Não informada"},{"nome":"Pêra","quantidade":"Não informada"},{"nome":"Polpa de maracujá","quantidade":"Não informada"},{"nome":"Polpa de cajá","quantidade":"Não informada"}]},
    {"categoria":"Limpeza e higiene","itens":[{"nome":"Sabão em pó","quantidade":"2 pacotes","observacao":"Verificar preço do sabão líquido para lavar louças"},{"nome":"Detergente para cozinha","quantidade":"Não informada"},{"nome":"Papel higiênico","quantidade":"Não informada"},{"nome":"Sabonetes","quantidade":"6 pacotes"},{"nome":"Bucha para lavar pratos","quantidade":"Não informada"},{"nome":"Limpa-multiuso Veja","quantidade":"Não informada"},{"nome":"Inseticida","quantidade":"Não informada"},{"nome":"Saco de lixo","quantidade":"Não informada"},{"nome":"Pasta de Dente","quantidade":"Não informada"},{"nome":"Desodorante","quantidade":"Não informada"}]},
    {"categoria":"Utensílios domésticos","itens":[{"nome":"Rodo","quantidade":"1 unidade"},{"nome":"Vassoura","quantidade":"1 unidade"},{"nome":"Triturador de legumes","quantidade":"1 unidade","observacao":"Verificar disponibilidade para venda"}]}
  ]$catalogo$::jsonb
)
on conflict (id) do nothing;

update public.lista_compras_catalogo as catalogo
set produtos = (
  select jsonb_agg(
    case
      when categoria->>'categoria' = 'Outros alimentos'
        then jsonb_set(categoria, '{categoria}', '"Outros"'::jsonb)
      else categoria
    end
    order by ordem
  )
  from jsonb_array_elements(catalogo.produtos) with ordinality
    as categorias(categoria, ordem)
)
where catalogo.id = true
  and catalogo.produtos @> '[{"categoria":"Outros alimentos"}]'::jsonb;

update public.lista_compras_catalogo as catalogo
set produtos = catalogo.produtos ||
  '[{"categoria":"Isabelle","itens":[]}]'::jsonb,
  updated_at = now()
where catalogo.id = true
  and not exists (
    select 1
    from jsonb_array_elements(catalogo.produtos) as categorias(categoria)
    where categorias.categoria->>'categoria' = 'Isabelle'
  );

create table if not exists public.lista_compras_estado (
  user_id uuid primary key references auth.users (id) on delete cascade,
  marcados text[] not null default array[]::text[],
  extras jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create or replace function public.normalizar_quantidades_itens(p_itens jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog, public
as $$
  select coalesce(
    jsonb_agg(
      case
        when not (item ? 'quantidade')
          or jsonb_typeof(item->'quantidade') <> 'string'
          or coalesce(btrim(item->>'unidade'), '') <> '' then item
        when btrim(item->>'quantidade') = '' then item - 'quantidade'
        when lower(btrim(item->>'quantidade')) like 'não informada%' then
          item - 'quantidade'
        when partes.valores is not null then
          (item - 'quantidade') || jsonb_build_object(
            'quantidade', replace(partes.valores[1], ',', '.')::numeric
          ) || case
            when btrim(partes.valores[3]) = '' then '{}'::jsonb
            else jsonb_build_object('unidade', btrim(partes.valores[3]))
          end
        else
          (item - 'quantidade') || jsonb_build_object(
            'unidade', btrim(item->>'quantidade')
          )
      end
      order by item_ordem
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb))
    with ordinality as itens(item, item_ordem)
  cross join lateral (
    select regexp_match(
      item->>'quantidade',
      '^[[:space:]]*([0-9]+([.,][0-9]+)?)[[:space:]]*(.*)$'
    ) as valores
  ) as partes;
$$;

revoke all on function public.normalizar_quantidades_itens(jsonb)
  from public, anon, authenticated;

update public.lista_compras_catalogo as catalogo
set produtos = (
  select jsonb_agg(
    jsonb_set(
      categoria,
      '{itens}',
      public.normalizar_quantidades_itens(categoria->'itens')
    )
    order by categoria_ordem
  )
  from jsonb_array_elements(catalogo.produtos)
    with ordinality as categorias(categoria, categoria_ordem)
),
updated_at = now()
where catalogo.id = true
  and exists (
    select 1
    from jsonb_array_elements(catalogo.produtos) as categorias(categoria)
    cross join lateral jsonb_array_elements(categorias.categoria->'itens')
      as itens(item)
    where jsonb_typeof(itens.item->'quantidade') = 'string'
      and coalesce(btrim(itens.item->>'unidade'), '') = ''
  );

update public.lista_compras_estado as estado
set extras = public.normalizar_quantidades_itens(estado.extras)
where exists (
  select 1
  from jsonb_array_elements(estado.extras) as extras(extra)
  where jsonb_typeof(extras.extra->'quantidade') = 'string'
    and coalesce(btrim(extras.extra->>'unidade'), '') = ''
);

create or replace function public.remover_item_catalogo(
  p_categoria text,
  p_nome text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  linhas_alteradas integer;
begin
  if p_categoria is null or btrim(p_categoria) = ''
     or p_nome is null or btrim(p_nome) = '' then
    raise exception 'Categoria e nome do item são obrigatórios.'
      using errcode = '22023';
  end if;

  update public.lista_compras_catalogo as catalogo
  set produtos = (
    select jsonb_agg(
      case
        when categoria->>'categoria' = p_categoria then
          jsonb_set(
            categoria,
            '{itens}',
            coalesce(
              (
                select jsonb_agg(item order by item_ordem)
                from jsonb_array_elements(categoria->'itens')
                  with ordinality as itens(item, item_ordem)
                where item->>'nome' <> p_nome
              ),
              '[]'::jsonb
            )
          )
        else categoria
      end
      order by categoria_ordem
    )
    from jsonb_array_elements(catalogo.produtos)
      with ordinality as categorias(categoria, categoria_ordem)
  ),
  updated_at = now()
  where catalogo.id = true
    and exists (
      select 1
      from jsonb_array_elements(catalogo.produtos)
        as categorias(categoria)
      cross join lateral jsonb_array_elements(categorias.categoria->'itens')
        as itens(item)
      where categorias.categoria->>'categoria' = p_categoria
        and itens.item->>'nome' = p_nome
    );

  get diagnostics linhas_alteradas = row_count;
  if linhas_alteradas = 0 then
    return false;
  end if;

  update public.lista_compras_estado
  set marcados = array_remove(marcados, p_categoria || '|' || p_nome),
      updated_at = now()
  where (p_categoria || '|' || p_nome) = any(marcados);

  return true;
end;
$$;

revoke all on function public.remover_item_catalogo(text, text) from public, anon;
grant execute on function public.remover_item_catalogo(text, text) to authenticated;

drop function if exists public.atualizar_item_catalogo(
  text, text, text, text, text, text
);
drop function if exists public.atualizar_item_catalogo(
  text, text, text, text, text, numeric, text
);

create or replace function public.atualizar_item_catalogo(
  p_categoria_atual text,
  p_nome_atual text,
  p_categoria_nova text,
  p_nome_novo text,
  p_quantidade_nova numeric,
  p_unidade_nova text,
  p_preco_novo numeric,
  p_observacao_nova text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  item_atual jsonb;
  item_editado jsonb;
  id_antigo text;
  id_novo text;
begin
  if p_categoria_atual is null or btrim(p_categoria_atual) = ''
     or p_nome_atual is null or btrim(p_nome_atual) = ''
     or p_categoria_nova is null or btrim(p_categoria_nova) = ''
    or p_nome_novo is null or btrim(p_nome_novo) = ''
    or p_quantidade_nova < 0
    or p_preco_novo < 0 then
    raise exception 'Categoria e nome do item são obrigatórios.'
      using errcode = '22023';
  end if;

  select itens.item
  into item_atual
  from public.lista_compras_catalogo as catalogo
  cross join lateral jsonb_array_elements(catalogo.produtos)
    as categorias(categoria)
  cross join lateral jsonb_array_elements(categorias.categoria->'itens')
    as itens(item)
  where catalogo.id = true
    and categorias.categoria->>'categoria' = p_categoria_atual
    and itens.item->>'nome' = p_nome_atual
  limit 1;

  if item_atual is null or not exists (
    select 1
    from public.lista_compras_catalogo as catalogo
    cross join lateral jsonb_array_elements(catalogo.produtos)
      as categorias(categoria)
    where catalogo.id = true
      and categorias.categoria->>'categoria' = p_categoria_nova
  ) then
    return false;
  end if;

  if exists (
    select 1
    from public.lista_compras_catalogo as catalogo
    cross join lateral jsonb_array_elements(catalogo.produtos)
      as categorias(categoria)
    cross join lateral jsonb_array_elements(categorias.categoria->'itens')
      as itens(item)
    where catalogo.id = true
      and categorias.categoria->>'categoria' = p_categoria_nova
      and itens.item->>'nome' = btrim(p_nome_novo)
      and not (
        categorias.categoria->>'categoria' = p_categoria_atual
        and itens.item->>'nome' = p_nome_atual
      )
  ) then
    return false;
  end if;

  if jsonb_typeof(item_atual) = 'string' then
    item_atual := jsonb_build_object('nome', item_atual #>> '{}');
  end if;
  item_editado := jsonb_set(
    item_atual,
    '{nome}',
    to_jsonb(btrim(p_nome_novo)),
    true
  );

  if p_quantidade_nova is null then
    item_editado := item_editado - 'quantidade';
  else
    item_editado := jsonb_set(
      item_editado,
      '{quantidade}',
      to_jsonb(p_quantidade_nova),
      true
    );
  end if;

  if p_unidade_nova is null or btrim(p_unidade_nova) = '' then
    item_editado := item_editado - 'unidade';
  else
    item_editado := jsonb_set(
      item_editado,
      '{unidade}',
      to_jsonb(btrim(p_unidade_nova)),
      true
    );
  end if;

  if p_preco_novo is null then
    item_editado := item_editado - 'preco_aproximado';
  else
    item_editado := jsonb_set(
      item_editado,
      '{preco_aproximado}',
      to_jsonb(p_preco_novo),
      true
    );
  end if;

  if p_observacao_nova is null or btrim(p_observacao_nova) = '' then
    item_editado := item_editado - 'observacao';
  else
    item_editado := jsonb_set(
      item_editado,
      '{observacao}',
      to_jsonb(btrim(p_observacao_nova)),
      true
    );
  end if;

  update public.lista_compras_catalogo as catalogo
  set produtos = (
    select jsonb_agg(
      case
        when categoria->>'categoria' = p_categoria_atual then
          jsonb_set(
            categoria,
            '{itens}',
            case
              when p_categoria_atual = p_categoria_nova then (
                select jsonb_agg(
                  case
                    when item->>'nome' = p_nome_atual then item_editado
                    else item
                  end
                  order by item_ordem
                )
                from jsonb_array_elements(categoria->'itens')
                  with ordinality as itens(item, item_ordem)
              )
              else coalesce(
                (
                  select jsonb_agg(item order by item_ordem)
                  from jsonb_array_elements(categoria->'itens')
                    with ordinality as itens(item, item_ordem)
                  where item->>'nome' <> p_nome_atual
                ),
                '[]'::jsonb
              )
            end
          )
        when categoria->>'categoria' = p_categoria_nova then
          jsonb_set(
            categoria,
            '{itens}',
            coalesce(categoria->'itens', '[]'::jsonb) ||
              jsonb_build_array(item_editado)
          )
        else categoria
      end
      order by categoria_ordem
    )
    from jsonb_array_elements(catalogo.produtos)
      with ordinality as categorias(categoria, categoria_ordem)
  ),
  updated_at = now()
  where catalogo.id = true;

  id_antigo := p_categoria_atual || '|' || p_nome_atual;
  id_novo := p_categoria_nova || '|' || btrim(p_nome_novo);
  if id_antigo <> id_novo then
    update public.lista_compras_estado
    set marcados = array_replace(marcados, id_antigo, id_novo),
        updated_at = now()
    where id_antigo = any(marcados);
  end if;

  return true;
end;
$$;

revoke all on function public.atualizar_item_catalogo(
  text, text, text, text, numeric, text, numeric, text
) from public, anon;
grant execute on function public.atualizar_item_catalogo(
  text, text, text, text, numeric, text, numeric, text
) to authenticated;

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

update public.lista_compras_estado
set marcados = array(
  select case
    when marcado like 'Outros alimentos|%'
      then replace(marcado, 'Outros alimentos|', 'Outros|')
    else marcado
  end
  from unnest(marcados) with ordinality as itens(marcado, ordem)
  order by ordem
)
where exists (
  select 1
  from unnest(marcados) as itens(marcado)
  where marcado like 'Outros alimentos|%'
);

update public.lista_compras_estado
set extras = (
  select jsonb_agg(
    case
      when extra->>'categoria' = 'Outros alimentos'
        then jsonb_set(extra, '{categoria}', '"Outros"'::jsonb)
      else extra
    end
    order by ordem
  )
  from jsonb_array_elements(lista_compras_estado.extras) with ordinality
    as itens(extra, ordem)
)
where extras @> '[{"categoria":"Outros alimentos"}]'::jsonb;