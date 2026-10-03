# tampa-virtual

Para MacBook com o sensor da tampa quebrado (lid angle sensor): fechar a tampa não faz nada.

Usa o sensor de luz ambiente, que fica escuro com a tampa fechada, para imitar a tampa:

- fechou, com monitor externo e na tomada: apaga a tela interna e segue nos monitores
- fechou, sem monitor ou na bateria: repouso
- abriu: religa a tela interna

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/wanderfran/tampa-virtual/main/instalar.sh | bash
```

## Remover

```bash
curl -fsSL https://raw.githubusercontent.com/wanderfran/tampa-virtual/main/desinstalar.sh | bash
```

## Recompilar

```bash
swiftc -O tampa.swift -o tampa-virtual
```

Limitação: reage à luz CAINDO de repente. Com o quarto já totalmente escuro, fechar a tampa não é percebido (assim ele não apaga com alguém usando no escuro).

Registro em `~/Library/Logs/tampa-virtual.log`. Testado em MacBook Pro 14" M1 Pro (MacBookPro18,3), macOS 26.5.
