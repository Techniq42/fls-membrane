# Start from nothing

The rest of this repo assumes you already have a server with Postgres on it. This page is the part before that, how you get from *nothing* to *a box that's yours*, without being technical.

**The move that makes this possible:** you don't run these steps by hand. You hand this file to **Claude Code, the app that can actually operate a machine**, running on the AI subscription you already pay for, and you tell it: *"Set this up for me, explain each step before you do it, and stop if anything looks wrong."* Read it yourself first if you like. Then let it drive. You direct, the machine does the wiring.

## What you need

- A card. The box runs about **$6 to $12 a month**, rent you pay a hosting company for the server, not a fee to anyone here.
- An **AI subscription you already have** (the kind Claude Code runs on). The intelligence stays rented and outside the box. You're not buying a brain; you're wiring one you already rent to a box you own.
- About an hour, most of it watching Claude Code work.

## Step 1 — Get the box

Rent a small Ubuntu server from any hosting company. You want roughly **4 to 6 vCPU, 8 to 11 GB RAM, no graphics card**, small on purpose, a router not a brain. When it asks which operating system, pick **Ubuntu 24.04 LTS**.

The box this very project runs on is exactly that class: Ubuntu 24.04, 4 vCPU, 8 GB RAM, a few dollars a month. Any mainstream host with a budget tier works. Because you own the box, you can move it to a different host later without losing a thing, so you're not marrying anyone. If you're not sure which to pick, paste Claude Code a couple you found and ask it to compare them for what you need.

When it's created, the host gives you an **address** (an IP) and a **way to log in** (a password or an SSH key). Hand those to Claude Code.

## Step 2 — Let Claude Code in

This is the piece the repo never spelled out, so here it is plainly.

Claude Code runs on **your** computer, on your own AI subscription. It reaches your box the ordinary way a technician would, over SSH, using the address and login the host gave you. You paste those into Claude Code and say *"log into my server and set it up."* On the first connection it makes a key so you're not passing a password around after that.

Two things stay true, and they're the whole point:

- **The intelligence stays outside the box.** Your subscription runs on your computer; the server only receives the commands. You are not installing a brain on the box or paying to rent one twice.
- **Your files and data stay ON the box, behind your wall.** Claude Code operates the machine; it never moves your data into the subscription.

For your own setup you connect as the box's **administrator**, because it's your box. The locked-down "reach one thing and nothing else" kind of access is Step 6, and that's for other people you invite in, never for you.

## Step 3 — Base install

Tell Claude Code to install the two things the box needs, and nothing more.

- **PostgreSQL**, where your coordination lives:
  ```bash
  sudo apt update && sudo apt install -y postgresql
  ```
  Then, one time, make yourself a database user so your data belongs to *you*, not to the system's admin account:
  ```bash
  sudo -u postgres createuser --superuser "$(whoami)"
  ```
  (That one line is the piece a fresh box is missing. Without it, the next step can't create a database in your name.)

- **Caddy**, which serves your website with automatic HTTPS, the little padlock, and renews the certificate for you so you never think about it:
  ```bash
  sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
  sudo apt update && sudo apt install -y caddy
  ```
  Caddy is how we front everything on the box.

## Step 4 — Stand up the membrane

This part the repo already documents. From the box:

```bash
git clone https://github.com/Techniq42/fls-membrane && cd fls-membrane
bash membrane.sh mydb setup
```

That one command makes a database that's yours (it's named `mydb` here, call it anything) and loads the whole capability layer into it: the five lanes, the board, escalation, tickets, handoffs. See `README.md` for the round-trip demo. Your data stays behind your wall.

## Step 5 — Serve your site off the same box

One box, one bill, no separate hosting company holding your website hostage. Put your site's files in a folder (say `/srv/mysite`), point your domain's DNS at the box's address, and give Caddy this much:

```
yourdomain.com {
    root * /srv/mysite
    file_server
    encode gzip
}
```

That's the whole config. Caddy fetches and renews the HTTPS certificate automatically from there. (A few budget hosts block the automatic certificate check; if yours does, Claude Code can switch it to a DNS-based check instead, it'll know how. We hit exactly this and it's a two-line fix.)

## Step 6 — Open one caged door (optional, for working with others)

When you want another group to reach *one* thing on your box and nothing else, you open a scoped, revocable door, never the whole house:

```bash
bash add-caged-seat.sh   # see 04-caged-seats.md for what it does and why
```

This is the arms-room model: a key that opens exactly one lock. The parts you're protecting stay structurally unreachable.

## The safety, in one line

Everything you're protecting is walled off by default; you open only the part you mean to. A guest reaches exactly what you offer, no rifling through the cabinets. Security built into the walls, not watched at the door.

---

**Stuck?** Every step above is something you can paste to Claude Code with "do this and explain it." The build is Apache-2.0, yours to run, fork, and change. A link back to the source keeps the lineage; that's the only ask.
