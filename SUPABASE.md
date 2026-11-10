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

1. No painel do Supabase, execute novamente o conteúdo atualizado de
   `supabase.sql` no SQL Editor. Além da tabela de estado, ele cria e preenche o
   catálogo inicial em `lista_compras_catalogo`. A carga inicial não substitui
   um catálogo que já exista.
2. Em Authentication, habilite cadastro por e-mail e senha. Configure a
   confirmação de e-mail conforme sua preferência.
3. Em Authentication > URL Configuration, adicione a URL publicada do GitHub
   Pages à lista de URLs permitidas. Para um projeto de repositório, ela costuma
   ter o formato `https://USUARIO.github.io/REPOSITORIO/`; para um site de usuário,
   `https://USUARIO.github.io/`.
4. Em `index.html`, substitua `https://SEU-PROJETO.supabase.co` pela Project URL e
   `SUA_CHAVE_PUBLICAVEL` pela chave publishable/anon do projeto.
5. Publique os arquivos no GitHub Pages e use a mesma conta em cada dispositivo.

O catálogo fica no Supabase e é compartilhado entre usuários autenticados.
Inclusões pelo formulário e pela importação CSV são gravadas no catálogo
compartilhado. Ao reaplicar `supabase.sql`, extras pessoais antigos de todas as
contas são migrados para o catálogo; após a migração, eles deixam de ser privados
e ficam visíveis para todos. Itens repetidos na mesma categoria não são
duplicados, e os itens marcados continuam marcados. O botão de remoção usa a função
`remover_item_catalogo` para excluir um item do catálogo compartilhado, afetando
todos os usuários. A função também limpa as marcações desse produto nas listas.
Edições do catálogo usam `atualizar_item_catalogo` e também afetam todos os
usuários, preservando as marcações quando nome ou categoria mudam. Marcações e
seleções continuam sincronizadas por usuário.

## Testes E2E com Playwright

Na raiz do projeto, crie um `.env` local com as chaves `usuario_1`, `senha_1`,
`usuario_2` e `senha_2`. Não compartilhe esse arquivo nem remova-o do
`.gitignore`. A suíte verifica acesso anônimo/autenticado, downloads do modelo e
do catálogo, validação e resumo de importação CSV, além do compartilhamento de
um produto entre as duas contas.

Com GNU Make e Node.js instalados, execute `make test-e2e`. O alvo instala as
dependências e o Chromium quando necessário e inicia um servidor local. Para
abrir o navegador durante os testes, execute `make test-e2e-visual`. Também é
possível executar manualmente: `npm install`, `npx playwright install chromium`
e `npm run test:e2e`; para navegador visível, use `npm run test:e2e:headed`.

Os testes que importam produtos usam nomes temporários e removem os registros
criados pela própria interface ao final.
O campo opcional `preco_aproximado` é editado no formulário de edição, aparece
em cada item e é tratado como preço unitário: o total aproximado soma preço ×
quantidade, considerando uma unidade quando a quantidade estiver vazia. Os
campos `quantidade` (numérico) e `unidade` (texto) são armazenados
separadamente. Ao reaplicar o SQL, valores antigos como `2 pacotes` são
migrados para esses campos. A edição oferece as mesmas opções de unidade da
inclusão; o preço não é solicitado ao adicionar um item novo.

## CSV de produtos

No fim da página, use **Exportar CSV** para baixar os produtos do catálogo
compartilhado ou **Baixar modelo** para obter um arquivo somente com os
cabeçalhos. O CSV usa UTF-8 com BOM e ponto e vírgula como delimitador. As
colunas são `categoria`, `nome`, `quantidade`, `unidade`, `preco_aproximado` e
`observacao`.

Para importar, preencha o modelo e selecione o arquivo CSV. Categoria e nome
são obrigatórios; quantidade e preço devem ser números não negativos quando
informados. Linhas inválidas aparecem no resumo com o número da linha. A
importação acrescenta apenas produtos que ainda não existam na mesma categoria,
comparando nome e categoria sem diferença entre maiúsculas/minúsculas ou espaços
excedentes. Produtos já existentes não são alterados; categorias novas são
criadas automaticamente. A primeira ocorrência válida no próprio arquivo é
considerada e as seguintes são contadas como existentes.

O catálogo é compartilhado: produtos importados ficam visíveis a todos os
usuários. A gravação é feita pela função `importar_itens_catalogo`, disponível
somente para usuários autenticados; a tabela continua sem permissão de escrita
direta pelo cliente. Reaplique `supabase.sql` no SQL Editor para criar/atualizar
a função antes de usar a importação.

## Limite de segurança

Uma chave que o navegador usa não pode ser mantida secreta em um site estático.
Esta configuração é apropriada para a chave publicável com RLS, mas não atende a
um requisito de esconder até mesmo essa chave. Para isso, seria necessário usar
um backend, como uma Supabase Edge Function, e não chamar o banco diretamente
do GitHub Pages.
