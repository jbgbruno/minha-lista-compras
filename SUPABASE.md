# Configurar Supabase

## Credenciais

O GitHub Pages executa o JavaScript no navegador. Portanto, qualquer valor usado
para conectar diretamente ao Supabase ficará visível para visitantes. Configure
somente:

- A URL do projeto.
- A chave `publishable` (ou a chave legada `anon`).

Essas chaves identificam o projeto, mas não são segredos. A proteção dos dados é
feita pelo login e pelas políticas RLS criadas em `supabase.sql`. Nunca coloque
`service_role`, senha do banco ou outro segredo no HTML, no GitHub ou em variáveis
de build do GitHub Pages.

## Ativar

1. No painel do Supabase, execute o conteúdo de `supabase.sql` no SQL Editor.
2. Em Authentication, habilite cadastro por e-mail e senha. Configure a
   confirmação de e-mail conforme sua preferência.
3. Em Authentication > URL Configuration, adicione a URL publicada do GitHub
   Pages à lista de URLs permitidas. Para um projeto de repositório, ela costuma
   ter o formato `https://USUARIO.github.io/REPOSITORIO/`; para um site de usuário,
   `https://USUARIO.github.io/`.
4. Em `index.html`, substitua `https://SEU-PROJETO.supabase.co` pela Project URL e
   `SUA_CHAVE_PUBLICAVEL` pela chave publishable/anon do projeto.
5. Publique os arquivos no GitHub Pages e use a mesma conta em cada dispositivo.

As marcações e os itens adicionados são sincronizados por usuário. O `lista.json`
continua sendo a lista base compartilhada e somente de leitura.

## Limite de segurança

Uma chave que o navegador usa não pode ser mantida secreta em um site estático.
Esta configuração é apropriada para a chave publicável com RLS, mas não atende a
um requisito de esconder até mesmo essa chave. Para isso, seria necessário usar
um backend, como uma Supabase Edge Function, e não chamar o banco diretamente
do GitHub Pages.
