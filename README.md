# blog.sh for iPhone and iPad

The whole of `./blog.sh` on a phone: the archive, the drafts, the queue,
one post with its properties and the actions that apply to it -- and,
in time, writing and editing with photographs from the camera roll.

It is a thin client. Nothing of the engine is reimplemented: the app
opens an SSH connection to the machine the blog lives on and runs
`./blog.sh <command> --json` there, the same commands a person types,
and draws the answers. The archive, the build and the deploy stay where
they are. That is why the engine grew a `--json` form for its screens
(1.10): one object per answer, every key always present, a refusal as an
object with a zero exit -- a contract a program can rely on.

Requires [blog.sh](https://github.com/DanielSnor/blog.sh) 1.10 on the
server and iOS 26 or later on the device.

## Building

Open `blogsh.xcodeproj` in Xcode 26 or later and run the `blogsh` scheme
on a simulator or a device of your own. There is nothing to install
first.

## License

MIT, see [LICENSE](LICENSE).
