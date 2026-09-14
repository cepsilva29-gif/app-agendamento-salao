# Manual do Painel da Empresa (para o dono do salão)

Guia sem termos técnicos para o dono do salão usar o `frontend-admin/index.html` no dia a dia:
atender clientes, organizar a equipe, fechar a agenda e conectar o WhatsApp da empresa.

**Versão interativa (recomendada para enviar ao cliente):**
https://claude.ai/code/artifact/95d872dc-006d-4355-af39-b18dbe61e7e9

O conteúdo abaixo é a versão em texto do mesmo guia, para ficar versionada junto do projeto.

> Sempre que este guia citar o nome de um botão ou campo, ele aparece entre aspas — é exatamente
> o texto que aparece na tela do painel.

## Sumário

1. [Entrar ou cadastrar sua empresa](#1-entrar-ou-cadastrar-sua-empresa)
2. [Conhecendo a tela principal](#2-conhecendo-a-tela-principal)
3. [Atender os agendamentos do dia](#3-atender-os-agendamentos-do-dia)
4. [Cadastrar seus serviços](#4-cadastrar-seus-serviços)
5. [Cadastrar sua equipe](#5-cadastrar-sua-equipe)
6. [Fechar a agenda](#6-fechar-a-agenda)
7. [Conectar o WhatsApp da empresa](#7-conectar-o-whatsapp-da-empresa)
8. [Compartilhar o link de agendamento](#8-compartilhar-o-link-de-agendamento)
9. [Perguntas frequentes](#9-perguntas-frequentes)

## 1. Entrar ou cadastrar sua empresa

A primeira tela do painel tem duas abas: "Entrar" e "Cadastrar empresa". Use a segunda só na
primeira vez.

- **Nome da empresa** — o nome do seu salão, do jeito que aparece para você no topo do painel.
- **Identificador único** — uma palavra curta, só com letras minúsculas, números e hífen (ex:
  `salao-da-ana`). Ela entra no link que seus clientes vão usar para agendar — escolha algo fácil
  de lembrar, porque depois de criado não muda sozinho.
- **WhatsApp da empresa** — o número que recebe o aviso de cada novo agendamento. Digite só
  números, com código do país: `55` + DDD + número. Exemplo para (11) 99999-8888: `5511999998888`.
- **Colaboradores** — opcional aqui: nomes da sua equipe separados por vírgula. Se pular, você
  cadastra depois em [Cadastrar sua equipe](#5-cadastrar-sua-equipe).
- **E-mail e Senha** — seu acesso ao painel. A senha precisa ter pelo menos 6 caracteres.

> **Importante:** cada salão tem um único login de administrador (o seu). Sua equipe entra apenas
> como nomes na agenda — eles não fazem login no painel.

Depois de clicar em "Criar conta", o painel abre direto, ou pede para você confirmar o e-mail
antes — siga o que aparecer na tela. Nas próximas vezes, use a aba "Entrar" com o e-mail e a senha
que você criou.

## 2. Conhecendo a tela principal

É a tela que abre logo depois do login. Ela mostra os agendamentos de um dia por vez, escolhido
no campo de data no topo.

- **Agendamentos hoje** — quantos atendimentos existem na data escolhida, de qualquer status.
- **Faturamento estimado** — soma dos preços dos serviços confirmados ou finalizados naquele dia.
- **Cancelados** — quantos desses agendamentos foram cancelados.

Abaixo dos cartões, a lista mostra cada agendamento com hora, nome do cliente, WhatsApp (clique
para abrir a conversa), serviço e preço, colaborador responsável e o status:

- **Confirmado** — ainda vai acontecer.
- **Finalizado** — já foi atendido.
- **Cancelado** — não vai mais acontecer.

A lista se atualiza sozinha a cada 1 minuto. Se quiser forçar uma atualização na hora, clique em
"Atualizar" ao lado do campo de data.

No painel lateral, o **ranking de colaboradores** mostra quem mais atendeu naquele dia — os três
primeiros ganham medalha (🥇🥈🥉), com o número de atendimentos e o valor gerado por cada um.

## 3. Atender os agendamentos do dia

Cada agendamento com status "Confirmado" tem dois botões na coluna Ações — os já finalizados ou
cancelados não têm mais nenhuma ação disponível.

1. Quando a cliente terminar o atendimento, clique em "Finalizado". Uma janela pede confirmação —
   clique em "Confirmar".
2. Se o cliente não for aparecer, clique em "Cancelar" em vez disso. Confirme na janela que abre.
   O cliente recebe um aviso automático pelo WhatsApp avisando do cancelamento.

> **Atenção:** essas duas ações não têm volta pelo painel. Se marcar o errado, é preciso ajustar
> manualmente com quem administra o sistema para você.

## 4. Cadastrar seus serviços

O card "Serviços", na lateral, é o catálogo que seus clientes veem na hora de agendar.

- **Nome do serviço** — como vai aparecer para o cliente (ex: "Corte Masculino", "Escova").
- **Preço (R$)** — valor cobrado pelo serviço.
- **Duração (min)** — quanto tempo o serviço ocupa na agenda; é o que garante que dois horários
  não se sobreponham.

Preencha os três campos e clique em "Adicionar serviço". Ele aparece na lista "Catálogo", abaixo
do formulário.

Para corrigir preço, duração ou nome de um serviço já cadastrado, edite direto nos campos da
lista Catálogo e clique em "Salvar" naquele mesmo item.

> **Dica:** desmarque a caixinha "Ativo" de um serviço para escondê-lo do site de agendamento sem
> apagar o histórico — ele fica esmaecido na lista, e você pode marcar "Ativo" de novo quando
> quiser voltar a oferecê-lo.

## 5. Cadastrar sua equipe

O card "Colaboradores" guarda a lista de quem atende no seu salão — é o que aparece para o
cliente escolher na hora de agendar.

1. Digite os nomes separados por vírgula, por exemplo: `Carlos, Ana, Bruno`.
2. Clique em "Salvar lista".

> **Dica:** essa mesma lista alimenta o menu de colaborador ao fechar a agenda — cadastre a
> equipe aqui primeiro, antes de lançar uma folga ou férias para alguém.

## 6. Fechar a agenda

Use o card "Fechar agenda de um colaborador" para bloquear horários por folga, férias, consulta
ou qualquer outro motivo, sem precisar cancelar clientes um por um.

- **Colaborador** — quem vai ficar indisponível.
- **Data** — o dia do bloqueio.
- **Dia inteiro** — marcado por padrão. Desmarque para escolher um horário de início e fim
  específico, em vez do dia todo.
- **Motivo** — opcional, só para você lembrar depois por que fechou aquele horário.

Preencha e clique em "Fechar agenda". O bloqueio aparece na lista "Bloqueios ativos", abaixo —
enquanto estiver lá, o site de agendamento não oferece esses horários para aquele colaborador.

> **Dica:** mudou de ideia antes da data chegar? Clique em "Cancelar" ao lado do bloqueio na
> lista para reabrir a agenda na hora.

## 7. Conectar o WhatsApp da empresa

É esse número que envia, automaticamente, a confirmação de cada novo agendamento, os avisos de
cancelamento e o lembrete antes do horário marcado.

No card "WhatsApp", o selo mostra o estado atual: "Não conectado", "Conectando..." ou
"Conectado".

1. Clique em "Conectar WhatsApp". Um código QR aparece na tela.
2. No celular que vai ser o WhatsApp da empresa, abra o WhatsApp → **Aparelhos conectados** →
   **Conectar um aparelho**, e aponte a câmera para o código QR mostrado no painel.
3. O selo muda para "Conectado" assim que o celular confirmar a leitura.

> **Atenção:** o código QR vale por 2 minutos. Se demorar demais para escanear, ele expira —
> basta clicar em "Conectar WhatsApp" de novo para gerar um novo código.

Já conectado e precisa trocar de número ou desligar? Clique em "Desconectar", que aparece no
lugar do botão de conectar enquanto o WhatsApp estiver ativo.

## 8. Compartilhar o link de agendamento

É o endereço que você divulga para os clientes marcarem horário sozinhos, sem precisar te chamar
no WhatsApp.

Ele aparece no topo do painel, ao lado do nome da sua empresa, assim que o identificador único
cadastrado no cadastro é reconhecido — algo como `https://salao-da-ana.agenda.seudominio.com`.
Clique em "Copiar" para colar onde quiser.

> **Dica:** coloque esse link na bio do Instagram ou fixado no status do WhatsApp — o cliente
> escolhe lá o colaborador, o serviço e o horário, e o agendamento já cai direto na sua tela
> principal.

## 9. Perguntas frequentes

**Esqueci minha senha. Como recupero o acesso?**
O painel ainda não tem um botão de "esqueci a senha". Fale com quem configurou o sistema para o
seu salão para redefinir sua senha manualmente.

**Posso criar um login para cada colaborador da equipe?**
Não por enquanto. Cada empresa tem um único login de administrador (o seu). Colaboradores entram
apenas como nomes, cadastrados em [Cadastrar sua equipe](#5-cadastrar-sua-equipe), para
aparecerem nas opções de agendamento e bloqueio.

**Um agendamento novo não aparece na minha tela. O que fazer?**
A lista se atualiza sozinha a cada minuto, mas você também pode clicar em "Atualizar" para forçar
agora. Confira também se a data escolhida no topo é a mesma do agendamento.

**Desativei um serviço por engano. Perdi o cadastro dele?**
Não. Desmarcar "Ativo" só esconde o serviço do site de agendamento — todos os dados continuam no
Catálogo. Marque a caixinha de novo para reativar.

**O código QR do WhatsApp expirou antes de eu escanear. E agora?**
Sem problema: clique em "Conectar WhatsApp" outra vez para gerar um código novo.

**Cancelei um bloqueio de agenda por engano. Como desfaço?**
Cadastre o bloqueio de novo em [Fechar a agenda](#6-fechar-a-agenda), com a mesma data e
colaborador — o painel não tem um botão de "desfazer".

**O que significa cada cor na coluna Status?**
"Confirmado" ainda vai acontecer, "Finalizado" já foi atendido, "Cancelado" não vai mais
acontecer. Só agendamentos "Confirmado" têm botões de ação.

---

Guia feito para acompanhar o Painel da Empresa. Alguma dúvida que não está aqui? Fale com quem
configurou o sistema para o seu salão.
