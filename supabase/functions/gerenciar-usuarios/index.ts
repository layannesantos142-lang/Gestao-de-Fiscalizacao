// Edge Function: gerenciar-usuarios (projeto Fiscalização +)
// Cadastro de acessos por FILIAL e SETOR, feito somente pelo Compliance.
// Ações: criar, status (ativar/desativar), redefinir_senha, excluir.
// A chave service_role fica apenas no servidor (variável de ambiente da função), nunca no navegador.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-user-token',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

const PAPEIS = ['filial', 'juridico', 'compliance'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });

    // Quem está chamando? Token do login em "x-user-token" (ou Authorization)
    const ehJwt = (t: string) => t.split('.').length === 3;
    const candidatos = [
      req.headers.get('x-user-token') ?? '',
      (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
    ].filter(ehJwt);
    let user: { id: string } | null = null;
    for (const t of candidatos) {
      const { data } = await admin.auth.getUser(t);
      if (data && data.user) { user = data.user; break; }
    }
    if (!user) return json({ erro: 'Sessão inválida. Saia e entre novamente.' }, 401);
    const { data: eu } = await admin.from('perfis').select('papel, ativo').eq('id', user.id).maybeSingle();
    if (!eu || eu.papel !== 'compliance' || eu.ativo === false) return json({ erro: 'Apenas o Compliance pode cadastrar usuários.' }, 403);

    const b = await req.json();
    switch (b.acao) {
      case 'criar': {
        // conta por FILIAL + SETOR (o login é feito escolhendo filial e setor; o e-mail é interno)
        const filial = String(b.filial || '').trim().toUpperCase();
        const setor = String(b.setor || '').trim();
        const papel = String(b.papel || '');
        if (!filial || !setor || !b.senha) return json({ erro: 'Informe filial, setor e senha.' }, 400);
        if (String(b.senha).length < 8) return json({ erro: 'A senha precisa ter pelo menos 8 caracteres.' }, 400);
        if (!PAPEIS.includes(papel)) return json({ erro: 'Perfil inválido.' }, 400);
        const email = conta(filial, setor);
        const nome = String(b.nome || (filial + ' · ' + setor)).trim();
        // o que a conta pode visualizar (vazio = padrão do perfil)
        const vis = Array.isArray(b.filiais_visiveis) && b.filiais_visiveis.length ? b.filiais_visiveis.map((x: string) => String(x).toUpperCase()) : null;
        const { data, error } = await admin.auth.admin.createUser({
          email, password: b.senha, email_confirm: true, user_metadata: { nome, deve_trocar_senha: false }
        });
        if (error) return json({ erro: traduz(error.message) }, 400);
        const { error: e2 } = await admin.from('perfis')
          .upsert({ id: data.user.id, email, nome, papel, filial, setor, filiais_visiveis: vis, ativo: true });
        if (e2) { await admin.auth.admin.deleteUser(data.user.id); return json({ erro: e2.message }, 400); }
        return json({ ok: true, user_id: data.user.id, login: email });
      }
      case 'status': {
        if (b.user_id === user.id) return json({ erro: 'Você não pode desativar o seu próprio usuário.' }, 400);
        const ativo = !!b.ativo;
        const { error } = await admin.auth.admin.updateUserById(b.user_id, { ban_duration: ativo ? 'none' : '876000h' });
        if (error) return json({ erro: traduz(error.message) }, 400);
        await admin.from('perfis').update({ ativo }).eq('id', b.user_id);
        return json({ ok: true });
      }
      case 'redefinir_senha': {
        if (!b.senha || String(b.senha).length < 8) return json({ erro: 'A senha precisa ter pelo menos 8 caracteres.' }, 400);
        const { data: atual } = await admin.auth.admin.getUserById(b.user_id);
        const meta = { ...((atual && atual.user && atual.user.user_metadata) || {}), deve_trocar_senha: true };
        const { error } = await admin.auth.admin.updateUserById(b.user_id, { password: b.senha, user_metadata: meta });
        if (error) return json({ erro: traduz(error.message) }, 400);
        return json({ ok: true });
      }
      case 'excluir': {
        if (b.user_id === user.id) return json({ erro: 'Você não pode excluir o seu próprio usuário.' }, 400);
        const { error } = await admin.auth.admin.deleteUser(b.user_id);
        if (error) return json({ erro: traduz(error.message) }, 400);
        return json({ ok: true });
      }
      default:
        return json({ erro: 'Ação desconhecida.' }, 400);
    }
  } catch (e) {
    return json({ erro: (e as Error).message }, 500);
  }
});

// e-mail interno da conta: filial.setor@fiscalizacao.fc (o mesmo cálculo é feito na tela de login)
function conta(filial: string, setor: string) {
  const s = (x: string) => x.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return s(filial) + '.' + s(setor) + '@fiscalizacao.fc';
}

function traduz(msg: string) {
  if (/already been registered|already registered|exists/i.test(msg)) return 'Já existe uma conta para esta filial e setor.';
  if (/password/i.test(msg) && /weak|short|least/i.test(msg)) return 'Senha fraca: use pelo menos 8 caracteres, com letras e números.';
  if (/invalid.*email/i.test(msg)) return 'E-mail inválido.';
  return msg;
}
