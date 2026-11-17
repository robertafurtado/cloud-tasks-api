# Relatório - Trabalho final de Computação em Nuvem

Aluna: Roberta Albuquerque de Sá Furtado - 22552916
Trabalho individual, então fiz todas as etapas (repositório, CI/CD, EC2, rotas novas, testes e relatório).

## Links

- Repositório: https://github.com/robertafurtado/cloud-tasks-api
- Aplicação: http://34.206.31.13/health (enquanto a EC2 estiver ligada)
- PR 1 (rota delete): https://github.com/robertafurtado/cloud-tasks-api/pull/1
- PR 2 (rota /version): https://github.com/robertafurtado/cloud-tasks-api/pull/2
- CI no PR 1: https://github.com/robertafurtado/cloud-tasks-api/actions/runs/44144264949
- CI na main depois do merge do PR 1: https://github.com/robertafurtado/cloud-tasks-api/actions/runs/44144418975
- CD do PR 1: https://github.com/robertafurtado/cloud-tasks-api/actions/runs/44144592004
- CI no PR 2: https://github.com/robertafurtado/cloud-tasks-api/actions/runs/44144849554
- CI na main depois do merge do PR 2: https://github.com/robertafurtado/cloud-tasks-api/actions/runs/44144985646
- CD do PR 2: https://github.com/robertafurtado/cloud-tasks-api/actions/runs/44145115222

## Como ficou a esteira

```
feature/* --PR--> CI (pytest + docker build, nao publica)
                    |
                  merge
                    v
main --push--> CI (pytest + build + push ghcr.io/robertafurtado/cloud-tasks-api:SHA)
                    |
              CI passou (workflow_run)
                    v
CD job deploy (runner na EC2): docker pull da imagem do SHA, docker run -p 80:8000,
                               testa /health, se falhar volta a imagem anterior
CD job verify (runner do GitHub): curl http://IP/health e confere o /version
```

O professor proibiu liberar o SSH para 0.0.0.0/0 e os runners do GitHub não têm IP fixo. Como estou usando o AWS Academy Learner Lab, não dá para criar role no IAM, então não consegui usar OIDC nem SSM. A solução que usei foi instalar um runner do GitHub Actions dentro da própria EC2 (com o label `ec2-deploy`). O runner é quem se conecta no GitHub, então a EC2 não precisa receber SSH de fora e não precisei colocar chave SSH nos secrets. O job `deploy` roda nesse runner e o job `verify` roda num runner normal do GitHub, acessando o IP público pela porta 80.

Para baixar a imagem do GHCR o deploy faz login com o `GITHUB_TOKEN` do próprio job, que expira quando o job termina.

Para o runner não rodar código de qualquer um, marquei em Settings > Actions que PR de fork precisa de aprovação. O `cd.yml` é disparado por `workflow_run`, que usa sempre o arquivo da main.

## Infraestrutura

- AWS Academy Learner Lab, região us-east-1
- EC2 `cloud-tasks-api`: Ubuntu Server 24.04 LTS, t3.micro (2 vCPU, 1 GiB de RAM), disco gp3 de 8 GiB
- Elastic IP 34.206.31.13
- Docker instalado com o `scripts/setup-ec2-ubuntu.sh` (coloquei também 1 GiB de swap porque a t3.micro tem pouca memória)
- Contêiner `cloud-tasks-api` com `--restart unless-stopped`
- Dados no volume Docker `cloud-tasks-data`, montado em `/data` (o SQLite fica em `/data/tasks.db`)

Security group `cloud-tasks-sg`:

- entrada TCP 22 (SSH): só o meu IP, com /32
- entrada TCP 80 (HTTP): 0.0.0.0/0, para acessar a API
- saída: tudo liberado (padrão), para o apt, o docker pull e o runner falar com o GitHub

A porta 8000 não fica aberta. O Docker liga a porta 80 da EC2 na 8000 do contêiner, onde o gunicorn está rodando.

Secrets: só criei o `EC2_HOST` (usado no job verify). Também criei o environment `production`, liberado só para a branch main, e protegi a main para só aceitar merge por PR com os checks `test` e `image` passando. Não tem chave nem senha no código.

## O que mudei na API

- `DELETE /tasks/<id>`: retorna 204 quando apaga e 404 quando a tarefa não existe. Testes: `test_delete_task` e `test_delete_not_found`.
- `GET /version`: mostra o commit da imagem que está rodando (vem do `GIT_SHA` que a CI passa no build). Testes: `test_version` e `test_version_dev`. A CD usa essa rota para conferir se o commit no ar é o mesmo que foi feito o deploy.

## Evidências

- Nos runs de CI dos PRs, os passos de login e publicação no GHCR aparecem como pulados, e não tem nenhum run de CD para os PRs, só para os pushes na main.
- Cada merge gerou uma imagem no GHCR com o SHA do commit e um deploy automático.
- Depois do merge do PR 2, o http://34.206.31.13/version passou a mostrar `b4d8b188a16bac11085181e2223e1371b5f6420c`, que é o commit do merge.
- O DELETE funcionando na EC2 está em [evidencias/delete.txt](evidencias/delete.txt).
- Persistência ([evidencias/persistencia.txt](evidencias/persistencia.txt)): criei a tarefa 2 no contêiner `b6256d9e017c`. O deploy do PR 2 trocou o contêiner para `7696106c1dce` e a tarefa continuou. Depois apaguei o contêiner na mão (`docker rm -f`), subi de novo (`b71773fc55e5`) e a tarefa continuou lá, porque o banco fica no volume.
- Rollback ([evidencias/rollback.txt](evidencias/rollback.txt)): testei no meu computador fazendo deploy de uma imagem que não sobe. O `deploy.sh` viu que o /health não respondeu e voltou a versão anterior, sem perder a tarefa.

## Custos

Preços de referência em us-east-1: t3.micro US$ 0,0104/h, disco gp3 US$ 0,08 por GB/mês (uns US$ 0,0009/h para 8 GB) e IPv4 público/Elastic IP US$ 0,005/h. Dá mais ou menos US$ 0,016 por hora com a instância ligada, e no Learner Lab isso sai dos créditos. GitHub Actions e GHCR não tiveram custo porque o repositório é público.

Horas de uso e custo final: atualizo depois de apagar a instância.

Para encerrar vou terminar a instância, conferir se não sobrou volume, liberar o Elastic IP, apagar o security group e remover o runner no GitHub.

## Dificuldades

- O SSH ficava travado. O "My IP" do console pegou o meu IPv6, mas a conexão sai por IPv4. A AWS não deixou trocar o IPv6 por IPv4 na mesma regra, então apaguei e criei outra com o meu IPv4 /32.
- Quando troquei do 4G do celular para o Wi-Fi o meu IP mudou e tive que atualizar a regra da porta 22. O deploy não foi afetado porque não depende do meu IP.
- Achar uma forma de fazer o deploy sem abrir o SSH, já que no Learner Lab não dá para usar IAM. Resolvi com o runner na EC2.
- A t3.micro tem só 1 GiB de memória, então criei swap no script de setup.
