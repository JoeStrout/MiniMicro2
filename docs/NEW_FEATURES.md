Mini Micro 2 is meant to be fully backwards-compatibly with Mini Micro 1.  However, we may add a handful of new features, as long as they don't break any existing code, and stick to Mini Micro's design philosophy.

This file documents features we are seriously considering:

- Add [box-drawing characters](https://www.unicode.org/charts/PDF/U2500.pdf) to the text fonts.

- Put `scale`, `scrollX`, and `scrollY` on the Display base class, and make them work on all display types (except SolidColorDisplay, of course, which is conceptually an infinite plane of color).

- Add a **GradientDisplay** class which is similar to SolidColorDisplay, except that it is configured with two points (by default the center-top and center-bottom of the screen), and a list of colors.  It interpolates those colors smoothly those two points.

- **Fast vector/matrix math.**  This requires no new APIs, but just sneaking some new intrinsics into mathUtil.

- Allow `SpriteDisplay.sprites` to accept **nested lists**, and draw the sprites therein in depth-first order.

- Some way to know the **name of a physical key** (or the physical key corresponding to a given name).  Really crucial for dealing with nonstandard keyboard layouts.

- A dedicated machine state/debugging display -- something that lets you examine the current stack, variable values, display states, playing sounds, etc.

- Some kind of movie/video display?  (Details TBD.)

- Packaging tools -- in particular, something that makes it easier to package for (and deliver to?) itch.io?  Or export as an image disk?  Or desktop app with custom icon?  (Again, details TBD.)
