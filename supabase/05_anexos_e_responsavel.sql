-- =====================================================================
-- Fiscalização + — Anexos (Supabase Storage) e responsável do Jurídico
-- (rodar depois do 04_protocolo_e_id.sql)
-- Regra: nada do que é preenchido pode ser perdido -> anexos NÃO podem ser apagados nem substituídos.
-- =====================================================================

-- Quem do Jurídico está fazendo a análise
alter table public.chamados add column if not exists responsavel_juridico text;

-- ---------- Arquivos (bucket privado) ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('anexos', 'anexos', false, 20971520)            -- até 20 MB por arquivo
on conflict (id) do update set public = false, file_size_limit = 20971520;

-- caminho do arquivo: <ID do chamado>/<data>_<nome>  -> a pasta é o ID do chamado
drop policy if exists anexos_arquivo_ler on storage.objects;
create policy anexos_arquivo_ler on storage.objects for select to authenticated
  using (bucket_id = 'anexos' and public.pode_ver((storage.foldername(name))[1]));
drop policy if exists anexos_arquivo_enviar on storage.objects;
create policy anexos_arquivo_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'anexos' and public.pode_ver((storage.foldername(name))[1]));
-- sem política de update/delete: ninguém apaga nem troca um anexo pelo app

-- ---------- Registro dos anexos ----------
create table if not exists public.anexos (
  id          bigint generated always as identity primary key,
  chamado_id  text not null references public.chamados(id),
  categoria   text not null default 'geral',      -- geral | abertura | resposta_filial | mall | juridico
  nome        text not null,
  caminho     text not null unique,
  tamanho     bigint,
  tipo        text,
  papel       text,
  autor       text,
  enviado_por uuid references auth.users(id) default auth.uid(),
  criado_em   timestamptz not null default now()
);
create index if not exists anexos_chamado_idx on public.anexos (chamado_id);
alter table public.anexos enable row level security;
drop policy if exists anexos_ler on public.anexos;
create policy anexos_ler on public.anexos for select to authenticated using (public.pode_ver(chamado_id));
drop policy if exists anexos_gravar on public.anexos;
create policy anexos_gravar on public.anexos for insert to authenticated with check (public.pode_ver(chamado_id));

do $$ begin
  alter publication supabase_realtime add table public.anexos;
exception when duplicate_object then null; end $$;
