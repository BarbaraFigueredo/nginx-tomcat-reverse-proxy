# Load Balancer Nginx + Tomcat

Um ambiente de estudo/demonstração que simula um cenário clássico de infraestrutura web: um **load balancer Nginx** distribuindo requisições entre **duas instâncias de Tomcat**, tudo orquestrado via Docker Compose.

A ideia aqui não é construir uma aplicação nova, e sim reproduzir — em escala reduzida e na própria máquina — o tipo de arquitetura que roda por trás de sistemas em produção: múltiplas instâncias de uma aplicação Java, com um proxy reverso na frente cuidando do balanceamento de carga, headers de proxy e observabilidade básica via logs.

## O que esse projeto demonstra

- Configuração de **Nginx como reverse proxy / load balancer** (bloco `upstream`, algoritmo round-robin por padrão)
- Propagação correta de headers (`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`) — essenciais para a aplicação de origem saber quem realmente fez a requisição
- **Orquestração multi-container com Docker Compose**, incluindo `depends_on` para garantir ordem de inicialização
- Logging customizado no Nginx, registrando qual upstream atendeu cada requisição e o tempo de resposta
- Um **health check endpoint** isolado (`/nginx-health`), padrão comum em ambientes com Kubernetes/orquestradores que fazem probes de liveness
- Uma **aplicação Java (Spring MVC) real** sendo servida identicamente pelas duas instâncias de Tomcat, não só as páginas de exemplo do Tomcat

## Arquitetura

```
                ┌─────────────┐
   cliente ───▶ │    Nginx    │  (porta exposta no host)
                │ (load bal.) │
                └──────┬──────┘
                       │ upstream app_tomcat
            ┌──────────┴──────────┐
            ▼                     ▼
      ┌───────────┐         ┌───────────┐
      │  tomcat1  │         │  tomcat2  │
      │  :8080    │         │  :8080    │
      └───────────┘         └───────────┘
```

O Nginx recebe todo o tráfego e decide, requisição por requisição, para qual Tomcat encaminhar. Isso é o que permite, por exemplo, atualizar uma instância sem derrubar o serviço inteiro, ou simplesmente distribuir carga entre máquinas.

## Estrutura dos arquivos

| Arquivo | Para que serve |
|---|---|
| `docker-compose.yml` | Define os três serviços (`tomcat1`, `tomcat2`, `nginx`) e como eles se conectam |
| `default.conf` | Configuração do Nginx: upstream, proxy, headers e health check |
| `JavaWeb1/` | Aplicação Spring MVC que os dois Tomcats servem |

## A aplicação: JavaWeb1

Em vez de deixar os Tomcats servindo só as páginas de exemplo que vêm com a imagem oficial, os dois containers rodam uma aplicação **Spring MVC** de verdade (projeto `JavaWeb1/`, criado originalmente como scaffold padrão no NetBeans).

A página inicial foi editada para mostrar, a cada requisição, **o hostname do container que respondeu** e o horário do servidor — isso torna o balanceamento visível no próprio conteúdo da página, além do header `X-Upstream` do Nginx.

```yaml
tomcat1:
  image: tomcat:9.0-jdk17
  volumes:
    - ./JavaWeb1/dist/ROOT.war:/usr/local/tomcat/webapps/ROOT.war:ro
tomcat2:
  image: tomcat:9.0-jdk17
  volumes:
    - ./JavaWeb1/dist/ROOT.war:/usr/local/tomcat/webapps/ROOT.war:ro
```

O mesmo arquivo `ROOT.war` é montado como volume nos dois containers — ou seja, as duas instâncias servem exatamente o mesmo código, só que em processos (containers) diferentes. É por isso que a imagem oficial do Tomcat (que vem com a pasta `webapps` vazia) já sobe servindo essa aplicação direto na raiz (`/`), sem precisar copiar nada de `webapps.dist`.

### Como o WAR foi gerado

O projeto é um Spring MVC clássico (XML config, sem anotações, sem classes `.java` próprias — só JSPs e beans no `applicationContext.xml` / `dispatcher-servlet.xml`). Como não há compilação de Java envolvida, o WAR pode ser montado manualmente com o `jar` do próprio JDK, sem precisar instalar Ant:

```bash
cd JavaWeb1

# monta uma pasta temporária com o conteúdo do WAR:
# as páginas/configs ficam em web/, e os .jars do Spring (copiados
# pelo NetBeans num build anterior) ficam em build/web/WEB-INF/lib
rm -rf /tmp/war-staging && mkdir -p /tmp/war-staging
cp -r web/* /tmp/war-staging/
cp -r build/web/WEB-INF/lib /tmp/war-staging/WEB-INF/

mkdir -p dist
(cd /tmp/war-staging && jar cf ../ROOT.war -C . .)
cp /tmp/ROOT.war dist/ROOT.war
```

> O arquivo gerado (`JavaWeb1/dist/ROOT.war`) **fica versionado no repositório de propósito** — assim o projeto roda com `docker compose up -d` direto após o clone, sem precisar de NetBeans/Ant instalados. A pasta `JavaWeb1/build/` (cache de build do NetBeans, de onde vieram os `.jars` do Spring usados no passo acima) fica fora do git; só é necessária se você quiser editar o JSP e gerar um novo WAR.

## Como rodar

Pré-requisito: Docker e Docker Compose instalados.

```bash
# sobe os três containers em background
docker compose up -d

# confere se todo mundo subiu
docker compose ps
```

> **Nota sobre a porta:** o `docker-compose.yml` deste repositório expõe o Nginx na porta **9090** do host (`"9090:80"`). Se a porta 8080 estiver livre na sua máquina, sinta-se livre de trocar — eu mudei aqui porque já tinha outro serviço ocupando a 8080 localmente.

## Testando

```bash
# deve retornar 200 OK, com o header X-Upstream mostrando qual Tomcat atendeu
curl -I http://localhost:9090

# health check simples, independente dos Tomcats
curl http://localhost:9090/nginx-health
# -> ok
```

Repetindo o `curl -I` algumas vezes, é possível ver o header `X-Upstream` alternando entre os dois containers de Tomcat — essa é a prova de que o balanceamento está funcionando. Dá pra ver isso também abrindo `http://localhost:9090` no navegador e atualizando a página: o hostname exibido no corpo da página (que é o hostname do container Tomcat que atendeu) muda conforme o Nginx alterna entre `tomcat1` e `tomcat2`.

Para acompanhar em tempo real qual instância está respondendo cada requisição:

```bash
docker compose logs -f nginx
```

O `log_format detalhado` configurado no `default.conf` registra, para cada requisição: IP do cliente, status HTTP, qual upstream respondeu e o tempo de resposta.

## Encerrando

```bash
docker compose down
```

## Possíveis evoluções

Esse projeto foi pensado para ficar simples e didático, mas dá pra crescer em várias direções interessantes:

- Trocar o round-robin por outra estratégia (`least_conn`, `ip_hash` para sticky sessions)
- Adicionar health checks ativos no bloco `upstream` para o Nginx parar de mandar tráfego para uma instância que caiu
- Subir um `docker-compose.override.yml` com HTTPS (certificado self-signed) para simular TLS termination no Nginx
- Adicionar um controller de verdade (anotado, `@RestController`) no `JavaWeb1` para expor, por exemplo, um endpoint `/status` em JSON
