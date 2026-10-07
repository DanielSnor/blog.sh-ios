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

1. Build and run the app (below), tap the name on the first screen, add
   a blog there and enter the server's host, the account and the port.
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

What is the app's own and no blog's is under the gear; a blog's settings
-- where it is, its key -- are behind the key at the end of its row in
the list of blogs. The app's own are three: the colours (under *How it
looks*), and these two. The size of the type: the
app follows the size the system has, and under **Text size**
it can be set one to four steps above that. On a Mac, where the system
gives an iPad app one size of type and no way to another, the app
enlarges its faces by its own hand, by the same steps. Rows that hold a
name beside a value put the value under the name at the largest sizes,
and the preview of a post is enlarged with the rest. And the language:
the app is written in English, Czech and German and speaks the system's
unless told another under **Language** -- kept where the system keeps an
app's own language, and taken up when the app is next started.

## What is where

| the wizard says | the app |
|---|---|
| New post | a title, the text with the marks `/write/` offers over it, a key that opens it over the whole screen for writing and a preview of the post as the blog would show it, the tags, pictures and video with their descriptions -- sent as one delivery, the post arrives as a draft |
| A post -- edit the text, its properties and the actions on it | the last fifty posts -- under them, that they are the last fifty and that the archive has the rest -- then the crossroads: how the post begins, to know it is the one meant, and under that the text, a language, the properties with every key of that screen; the crossroads asks what the post is now every time it is come to, so a post retitled in its text or renamed in its properties is shown and asked for under what it is called now |
| The scheduled-post queue | the rows in publish order; a row opens its post, as in the archive; up, down, carry to a position -- by its number or by dragging the row there -- publish now, reschedule, cancel the schedule: the last two under the names the properties screen has for them, with a line under the rows that says the keys are behind a swipe and a hold |
| The archive | newest first, with the type, state and tag filters, the search, and a post opening to its crossroads |
| Trash | what is in it, a row restoring its post; under the rows the clearing out the terminal has two commands for -- empty the trash, remove the older versions -- each said in numbers and asked before it is done |
| The site | rebuild and deploy, with the two switches the command has |

A picture or a video goes with a post only when the text names it: one
picked and never put into the text stays on the device, and its card says
so. On a site of more than one language a post not written in all of them
is asked about before it is published or scheduled, the way the terminal
wants `--allow-partial` typed. What an action has to say and what it has
to ask next come as one message -- a post deleted says so, asks about the
rebuild, and its screens are left.

Where the terminal asks a question, the app asks it too; where it
rebuilds without asking, so does the app; where it asks whether to
rebuild now, the app asks.

## Looking before sending

Two looks, before anything leaves the device. The preview -- under the text
of a new post, of a post being edited, of a translation -- is the post as
the blog would show it, near enough: the text rendered the way the
`/write/` page renders it -- the same markdown, the same boxes where a
picture is missing or not on a line of its own -- in the blog's own
stylesheets. Two things it draws the blog's way rather than that page's:
the line `//--more--//`, which cuts a post in two, is a hairline, not
words; and pictures in a row are the gallery they are on the site -- two
side by side, an odd last one across both. And a picture chosen for a post is a key: behind it the
shots stand one to a page and large, each with the line that describes it
under it, to be written while looking at what it describes. A description
typed on a card goes into the mark the text has for that shot as it is
typed -- where the mark still says what the card said; one typed into the
text itself is the author's own wording and no card overwrites it, the
rule of `/write/`. The text is sent as it stands.

The text of a post is as tall as it asks, up to what stays in sight:
with a keyboard up it has everything down to the keyboard -- the tags
under it are not needed while writing -- and past that it moves inside
its own frame, so the caret is never behind the keyboard; without one it
has half the page. The screens for writing say what they are in the bar,
beside the way back, and leave the page to the text: a new post its
name, a post's text and its translation the post's title. Over the whole
screen the text has a tablet's whole width and most of a window's; the
lines stop growing at some hundred and ten letters, a measure that grows
with the type. A picture's mark goes into the text where the caret is --
a paragraph of its own, a blank line on each side and none doubled, the
rule of `/write/` -- and at the end only when the text was never
touched. The two keys on a picture's card are as tall as a finger needs.

A post's address can be handed to somebody from wherever the post is on
the screen: a key in the bar of its crossroads, its properties and its
preview, and **Share the link** in the menu of a row of the archive. It
opens the system's own sheet with the address and the title. The address
is the engine's to say (`props --json`, `url`): a published post's own,
and for a draft the hidden page the build keeps for it.

## What travels

What `/write/` sends, made on the device. A photograph is shrunk to
2560 px on its long edge and written as JPEG whatever it was, HEIC
included; a video is exported as H.264 in an MP4 at 720p, which every
browser plays. Neither carries where it was taken. The whole delivery has
to stay under the server's limit (`version --json` says it, `max_mb`),
measured on the encoded stream; the form says what is on the way and
refuses to send what the server would refuse.

## How it looks

A ground and the ink on it, by day and by night, and one accent: the
open blog's own. The engine says them with its identity (`version
--json`: `site.accent` and `site.palette`, the ground, the text, the text
beside it and the rules, for light and for dark), so each blog looks in
the app as its pages do -- with its favicon beside its name. A blog whose
engine says no palette yet, and the app before any blog, wear the app's
own: the blue the engine ships with. **Use the default colour scheme** in
Settings keeps the app to its own whatever blog is open -- for eyes a
blog's palette does not serve. The first screen is the blog at one glance -- what
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

## Tests

What the app works out by itself is tested: the marks over the text,
against the `/write/` page's own answers on some fifteen hundred cases;
the preview, against what that page's own JavaScript renders;
the line for `authorized_keys`; the icon nearest an accent; the engine's
answers as they are read; the blogs as they are written down, and taken
over from the settings of a build that had only one; a post's file, its
pictures' names, and the weight of a delivery against the server's limit.
The screens are not -- they are looked at.

```
xcodebuild test -project blogsh.xcodeproj -scheme blogsh \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The tests run inside the app, which stays idle while it hosts them: no
screen, and no connection to anybody's blog. What the engine answers is
its own to test, and it does, in its own suite.

## License

MIT, see [LICENSE](LICENSE). The typefaces in `blogsh/Fonts/` are their
authors', under the SIL Open Font License 1.1; each licence sits beside
its font.
