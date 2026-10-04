# blog.sh for iPhone and iPad

The whole of `./blog.sh` on a phone: the wizard's menu, entry for entry
and key for key. A new post with photographs, a post's text in
every language the site publishes, its properties and the actions on it,
the scheduled-post queue, the archive with its filters and search, the
trash, and the site's rebuild.

It is a thin client. Nothing of the engine is reimplemented: the app
opens an SSH connection to the machine the blog lives on and runs
`./blog.sh <command> --json` there, the same commands a person types,
and draws the answers. The archive, the build and the deploy stay where
they are. That is why the engine grew a `--json` form for every screen
and every key (1.10): one object per answer, every key always present, a
refusal as an object -- a contract a program can rely on.

Requires [blog.sh](https://github.com/DanielSnor/blog.sh) 1.10 on the
server and iOS 26 or later on the device.

## Setting it up

1. Build and run the app (below), open **Settings** under the gear and
   enter the server's host, the account and the port.
2. **Make the app's key.** It is made on the device and kept in its
   keychain; it never leaves it.
3. Say where the blog is on the server -- its directory -- and the app
   writes the line for the account's `~/.ssh/authorized_keys`. The line
   carries a forced command in front of the key, `scripts/remote.sh` in
   the blog's directory, which is all the key may ever run: one engine
   command at a time, or a delivery of files into `incoming/`. It never
   gets a shell. A blog inside a container is reached *through* the
   command that enters it (`sudo docker exec -i blog`), and a Ruby that is
   not on the server's own `PATH` through `env PATH=…`; the app puts
   either in front of the script and hands it the word SSH was asked for.
   See *Driving the engine from a program* in the engine's
   `docs/operations.md` for what the command allows and refuses.
4. **Test the connection.** The identity block the terminal shows above
   every screen appears; the server's key is remembered on first use and
   has to be the same every time after.

## More than one blog

The app holds as many blogs as you write. The name on the first screen is
the switch: tap it for the list, pick another, or add one. Each blog has
its own server, its own directory and its own key -- a key's forced
command names one blog's `scripts/remote.sh`, so one key is one blog and
nothing more, even when two blogs share a server and an account. A new
blog starts with the server of the one that was open -- a second blog
most often lives beside the first -- and asks for its directory and a key
of its own; removing a blog removes its key from the device, and the line
on the server is then yours to delete.
Switching changes everything the screen wears: the name, the favicon, the
accent, what waits in the queue.

## What is where

| the wizard says | the app |
|---|---|
| New post | a title, the text with the marks `/write/` offers over it and a key that opens it over the whole screen for writing, the tags, pictures and video with their descriptions -- sent as one delivery, the post arrives as a draft |
| A post -- edit the text, its properties and the actions on it | the last fifty posts, then the crossroads: the text, a language, the properties with every key of that screen |
| The scheduled-post queue | the rows in publish order; up, down, carry to a position -- by its number or by dragging the row there -- publish now, another time, return to drafts |
| The archive | newest first, with the type, state and tag filters, the search, and a post opening to its crossroads |
| Trash | what is in it, a row restoring its post |
| The site | rebuild and deploy, with the two switches the command has |

Where the terminal asks a question, the app asks it too; where it
rebuilds without asking, so does the app; where it asks whether to
rebuild now, the app asks.

## What travels

What `/write/` sends, made on the device. A photograph is shrunk to
2560 px on its long edge and written as JPEG whatever it was, HEIC
included; a video is exported as H.264 in an MP4 at 720p, which every
browser plays. Neither carries where it was taken. The whole delivery has
to stay under the server's limit (`version --json` says it, `max_mb`),
measured on the encoded stream; the form says what is on the way and
refuses to send what the server would refuse.

## How it looks

Paper and ink by day, ink on black by night, and one accent: the blog's
own, which the engine says with its identity (`version --json`), the way
`/write/` wears it -- with the blog's favicon beside its name. The first screen is the blog at one glance -- what
waits in the queue, how many drafts are in progress -- over the six
entries of the menu; a list is a name, a count, its filters as pills and
its rows; every other screen is plates on paper -- rows that belong
together on one card, a hairline between them -- with one filled button
for the one thing the screen is for, and what cannot be taken back set
apart in a colour of its own.

The icon on the home screen follows: its cursor takes the accent of the
blog the app was last opened with. An app cannot draw its icon while it
runs, only choose among those it was built with, so the catalog holds the
icon in thirty-six hues and the nearest is chosen. The system says so each
time an icon changes, and that notice is its own -- so the icon is set
when the app comes to the front, not while one switches blogs inside it.

An iPad on its side shows the menu beside the open screen. Held upright
it has room for one: the first screen is then a page of its own, two
thirds of the width and everything on it larger by the same measure, and
an open screen takes the whole of it, with the way back where a phone
has it.

Three voices of type: a terminal's face in lower case for what a screen
is -- IBM Plex Mono -- a sans for what it holds, a typewriter face for
what the engine says. The first two are bundled from `blogsh/Fonts/` with their
licences (SIL Open Font License 1.1) and registered at launch -- any
`.ttf` put there is. Take them out and the system's own stand in.

Under the search the first screen says the blog in numbers: posts and the
year of the first, words and the hours it takes to read them, tags, media,
and what the trash and the versions hold -- those two are keys to the
trash. The archive is counted (`stats --json`) after the screen itself is
up, and the numbers are kept with the blog, so the next launch shows them
at once.

## Building

Open `blogsh.xcodeproj` in Xcode 26 or later and run the `blogsh` scheme
on a simulator or a device of your own. The one dependency, Citadel for
SSH, is fetched by Xcode.

## License

MIT, see [LICENSE](LICENSE). The typefaces in `blogsh/Fonts/` are their
authors', under the SIL Open Font License 1.1; each licence sits beside
its font.
