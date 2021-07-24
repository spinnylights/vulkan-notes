# Vulkan notes

These are my notes on how Vulkan works (see `vulkan_notes.md`).
They're written kind of like a long article and I might tighten
them up into a proper tutorial or something eventually. Mostly
they are distilled from the [Vulkan spec
itself](https://www.khronos.org/registry/vulkan). The information
I've gathered here is more-or-less focused on what would be
relevant for someone making a 3D game engine, because that's what
I'm doing over at the [_Crypt Underworld_
repo](https://github.com/spinnylights/crypt_underworld).

The notes are written in
[Markdown](https://daringfireball.net/projects/markdown/). There
is a little Bash script `start` here you can use that will watch
the Markdown file for changes and convert it to HTML and
concatenate it with a header and footer when it notices any. It
will also open the finished web page in Firefox, and launch
[gVim](https://www.vim.org/) to edit the notes with. This is
obviously kind of specific to my environment but it might be
useful to you too if you have the various programs installed (in
addition to Firefox and gVim you should have the markdown CLI,
inotify-wait from
[inotify-tools](https://github.com/inotify-tools/inotify-tools),
and [Ruby](https://www.ruby-lang.org) available on your
`PATH`—check your distro's packages). `start` depends on the
script `do_on_save` which I have in my personal bindir but I have
included here for your convenience.

The notes themselves (`vulkan_notes.md`) are made available under
the [CC BY-SA
4.0](https://creativecommons.org/licenses/by-sa/4.0/legalcode)
license, and the scripts (`start` and `do_on-save`) are made
available under the
[GPL-3+](https://www.gnu.org/licenses/gpl-3.0.html). See
`COPYING.md` for details. There are a few things here made by
other people and the licenses and authorship information for
those things accompany them in the same directory where
applicable.
