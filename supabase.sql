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
    {"categoria":"Laticínios","itens":[{"nome":"Creme de leite","quantidade":"2 unidades"},{"nome":"Leite condensado","quantidade":"1 unidade"},{"nome":"Leite em pó","quantidade":"Não informada"},{"nome":"Queijo","quantidade":"Não informada"},{"nome":"Iogurte","quantidade":"Não informada"},{"nome":"Margarina","quantidade":"Não informada"}]},
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

create or replace function public.importar_itens_catalogo(p_itens jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_produtos jsonb;
  v_item jsonb;
  v_categoria_json jsonb;
  v_novo_item jsonb;
  v_resultados jsonb := '[]'::jsonb;
  v_linha integer;
  v_ordem bigint;
  v_indice_categoria bigint;
  v_categoria text;
  v_categoria_chave text;
  v_nome text;
  v_nome_chave text;
  v_unidade text;
  v_observacao text;
  v_quantidade numeric;
  v_preco numeric;
  v_tem_quantidade boolean;
  v_tem_preco boolean;
  v_mensagem text;
  v_status text;
  v_importados integer := 0;
  v_existentes integer := 0;
  v_erros integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_itens) is distinct from 'array' then
    raise exception 'A lista de produtos deve ser um array.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_itens) > 5000 then
    raise exception 'O limite é de 5000 linhas por importação.' using errcode = '22023';
  end if;

  select produtos
  into v_produtos
  from public.lista_compras_catalogo
  where id = true
  for update;

  if not found or jsonb_typeof(v_produtos) <> 'array' then
    raise exception 'O catálogo não está disponível.' using errcode = '22023';
  end if;

  for v_item, v_ordem in
    select valor, ordem
    from jsonb_array_elements(p_itens) with ordinality as entrada(valor, ordem)
  loop
    v_linha := v_ordem::integer;
    if jsonb_typeof(v_item) = 'object' then
      begin
        v_linha := coalesce(nullif(v_item->>'linha', '')::integer, v_linha);
      exception
        when invalid_text_representation or numeric_value_out_of_range then
          v_linha := v_ordem::integer;
      end;
    end if;
    v_status := 'erro';
    v_mensagem := null;

    if jsonb_typeof(v_item) <> 'object' then
      v_mensagem := 'registro inválido';
    else
      v_categoria := regexp_replace(btrim(coalesce(v_item->>'categoria', '')), '[[:space:]]+', ' ', 'g');
      v_nome := regexp_replace(btrim(coalesce(v_item->>'nome', '')), '[[:space:]]+', ' ', 'g');
      v_unidade := nullif(regexp_replace(btrim(coalesce(v_item->>'unidade', '')), '[[:space:]]+', ' ', 'g'), '');
      v_observacao := nullif(regexp_replace(btrim(coalesce(v_item->>'observacao', '')), '[[:space:]]+', ' ', 'g'), '');
      v_mensagem := null;

      if v_categoria = '' or v_nome = '' then
        v_mensagem := 'categoria e nome são obrigatórios';
      elsif char_length(v_nome) > 80 then
        v_mensagem := 'nome deve ter até 80 caracteres';
      elsif char_length(coalesce(v_observacao, '')) > 160 then
        v_mensagem := 'observação deve ter até 160 caracteres';
      end if;

      v_tem_quantidade := nullif(btrim(coalesce(v_item->>'quantidade', '')), '') is not null;
      v_tem_preco := nullif(btrim(coalesce(v_item->>'preco_aproximado', '')), '') is not null;
      v_quantidade := null;
      v_preco := null;
      if v_tem_quantidade and (v_item->>'quantidade') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' then
        v_mensagem := 'quantidade inválida';
      elsif v_tem_preco and (v_item->>'preco_aproximado') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' then
        v_mensagem := 'preço inválido';
      end if;
      if v_mensagem is null then
        begin
          if v_tem_quantidade then
            v_quantidade := (v_item->>'quantidade')::numeric;
            if v_quantidade < 0 then
              v_mensagem := 'quantidade não pode ser negativa';
            end if;
          end if;
          if v_tem_preco then
            v_preco := (v_item->>'preco_aproximado')::numeric;
            if v_preco < 0 then
              v_mensagem := 'preço não pode ser negativo';
            end if;
          end if;
        exception
          when invalid_text_representation or numeric_value_out_of_range then
            v_mensagem := 'quantidade ou preço inválido';
        end;
      end if;

      if v_mensagem is null then
        v_categoria_chave := lower(v_categoria);
        v_nome_chave := lower(v_nome);

        select ordem, valor
        into v_indice_categoria, v_categoria_json
        from jsonb_array_elements(v_produtos) with ordinality as categorias(valor, ordem)
        where lower(regexp_replace(btrim(coalesce(valor->>'categoria', '')), '[[:space:]]+', ' ', 'g')) = v_categoria_chave
        limit 1;

        if not found then
          v_indice_categoria := jsonb_array_length(v_produtos) + 1;
          v_categoria_json := jsonb_build_object('categoria', v_categoria, 'itens', '[]'::jsonb);
          v_produtos := v_produtos || jsonb_build_array(v_categoria_json);
        end if;

        if exists (
          select 1
          from jsonb_array_elements(coalesce(v_categoria_json->'itens', '[]'::jsonb)) as itens(valor)
          where lower(regexp_replace(btrim(coalesce(valor->>'nome', '')), '[[:space:]]+', ' ', 'g')) = v_nome_chave
        ) then
          v_status := 'existente';
          v_existentes := v_existentes + 1;
        else
          v_novo_item := jsonb_build_object('nome', v_nome);
          if v_tem_quantidade then
            v_novo_item := v_novo_item || jsonb_build_object('quantidade', v_quantidade);
          end if;
          if v_unidade is not null then
            v_novo_item := v_novo_item || jsonb_build_object('unidade', v_unidade);
          end if;
          if v_tem_preco then
            v_novo_item := v_novo_item || jsonb_build_object('preco_aproximado', v_preco);
          end if;
          if v_observacao is not null then
            v_novo_item := v_novo_item || jsonb_build_object('observacao', v_observacao);
          end if;
          v_produtos := jsonb_set(
            v_produtos,
            array[(v_indice_categoria - 1)::text, 'itens'],
            coalesce(v_categoria_json->'itens', '[]'::jsonb) || jsonb_build_array(v_novo_item),
            true
          );
          v_categoria_json := jsonb_set(
            v_categoria_json,
            '{itens}',
            coalesce(v_categoria_json->'itens', '[]'::jsonb) || jsonb_build_array(v_novo_item),
            true
          );
          v_status := 'importado';
          v_importados := v_importados + 1;
        end if;
      end if;
    end if;

    if v_status = 'erro' then
      v_erros := v_erros + 1;
    end if;
    v_resultados := v_resultados || jsonb_build_array(
      jsonb_build_object(
        'linha', v_linha,
        'status', v_status,
        'mensagem', v_mensagem
      )
    );
  end loop;

  if v_importados > 0 then
    update public.lista_compras_catalogo
    set produtos = v_produtos,
        updated_at = now()
    where id = true;
  end if;

  return jsonb_build_object(
    'importados', v_importados,
    'existentes', v_existentes,
    'erros', v_erros,
    'resultados', v_resultados
  );
end;
$$;

revoke all on function public.importar_itens_catalogo(jsonb) from public, anon;
grant execute on function public.importar_itens_catalogo(jsonb) to authenticated;