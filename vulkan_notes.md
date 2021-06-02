The text of this file is made available under the [CC BY-SA
4.0](https://creativecommons.org/licenses/by-sa/4.0/legalcode)
license. You can copy it, redistribute it, make your own work
based on it, etc. as long as you use the same license for both
this text and any work you make based on it, and give credit to
me (Zoë Sparks) for authorship of this text.

# Designing `Instance` and friends

## The lay of the land

Vulkan has a object called
[`VkInstance`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkInstance.html)
that represents the "top-level" interface between an
application and the Vulkan runtime. Only one instance of it
should exist at a time (in other words, it should be treated as a
[singleton](https://en.wikipedia.org/wiki/Singleton_pattern)).
Talking to Vulkan generally starts with the instantiation of a
`VkInstance`, and a group of other Vulkan objects are created
and/or destroyed via the `VkInstance` interface. This raises
ownership questions: who should be responsible for destroying the
objects created through a `VkInstance`?

Three objects are destroyed via the `VkInstance` interface, not
counting the `VkInstance` itself:
[`VkDebugUtilsMessengerEXT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDebugUtilsMessengerEXT.html),
[`VkDebugReportCallbackEXT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDebugReportCallbackEXT.html),
and
[`VkSurfaceKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSurfaceKHR.html).
`VkDebugUtilsMessengerEXT` and `VkDebugReportCallbackEXT` are
also created via the `VkInstance` interface, but
`VkSurfaceKHR` is not quite so simple. There *are* two ways of
creating a `VkSurfaceKHR` via the `VkInstance` interface:
[`vkCreateHeadlessSurfaceEXT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateHeadlessSurfaceEXT.html)
and
[`vkCreateDisplayPlaneSurfaceKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDisplayPlaneSurfaceKHR.html).
However, neither of these functions creates a surface that
represents a platform window. The Vulkan API includes a variety
of platform-specific functions for this, and platform abstraction
libraries like
[GLFW](https://www.glfw.org/docs/3.3/group__vulkan.html#ga1a24536bec3f80b08ead18e28e6ae965)
and
[SDL2](https://wiki.libsdl.org/SDL_Vulkan_CreateSurface?highlight=%28%5CbCategoryVulkan%5Cb%29%7C%28CategoryEnum%29%7C%28CategoryStruct%29)
include their own functions for creating a Vulkan surface
attached to a window. All these window-oriented functions take a
`VkInstance`/`VkInstance` as an argument. So, the paths through
which a `VkSurfaceKHR` can come into being always involve a
`VkInstance` somehow, but are not the unambiguous
responsibility of that `VkInstance`.

There is also a type of object that can be obtained from a
`VkInstance` without it needing to be instantiated:
`VkPhysicalDevice`. A `VkPhysicalDevice` is a representation
of a physical device available in the environment, and can be
obtained via
[`vkEnumeratePhysicalDevices()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkEnumeratePhysicalDevices.html).
You can use one of these to create a
[`VkDevice`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDevice.html),
a more abstract representation of a device, which is what you
actually send drawing commands to and the like.
`VkPhysicalDevice`s don't need to be destroyed, as they aren't
much more then a simple collection of data.

For the sake of completeness, `VkInstance` also has a function
[`vkEnumeratePhysicalDeviceGroups()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkEnumeratePhysicalDeviceGroups.html).
Two `VkPhysicalDevice`s are in the same group if they are
[more-or-less
identical](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-devices).
In this case, a single `VkDevice` can be made with a
[`VkDeviceGroupDeviceCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceGroupDeviceCreateInfo.html) to represent all
the `VkPhysicalDevice`s that share the same group. This is
mainly useful in environments like render farms and
supercomputers where many identical GPUs may be present on the
same system, so we don't really need to worry about it here.

## What should be a class?

Aside from lifetime management concerns, we also need to think
about the needs of our specific application. The Vulkan API is
very general—it supports a huge variety of use cases, from
offline rendering to nonvisual linear-algebra-heavy computation
to lightweight display driving for embedded devices. In our case,
we're developing a real-time, visual, user-space application
designed to run on home PCs.  Therefore, we may not want to hew
closely to the Vulkan API, as it may make the graphics interface
of our application unnecessarily complicated. On the other hand,
if we oversimplify our graphics API, it will be hard to take
advantage of the power Vulkan offers. We have to strike the right
balance between convenience and flexibility.

In theory, we might want a very simple API:

<pre class="language-cpp">
<code>
Game game;
Graphics gr;

while (game.run()) {
    gr.draw(game);
}
</pre>
</code>

In this case, the whole Vulkan API would be hidden behind our
`Graphics` class. Same goes for any platform abstraction library
we may be using, like GLFW or SDL2. Without some ability to
configure `Graphics`, our choice of graphics API (Vulkan) and
platform window solution will be fixed. That might not be a good
idea: graphics APIs, platform abstraction libraries, and
platforms themselves all come and go, and the degree to which
they all get along varies. If we keep our graphics representation
separate from our platform window representation, we will be able
to manage the communication between them from the outside, and
even swap one out for another if we define a standard interface
for them to communicate through.

Even if we never need to support multiple graphics APIs or
platforms, this strategy is also easier to understand from a
user's perspective. A graphics API is very complicated, whereas a
platform window is relatively simple; if we package the whole
window API into the graphics API, the window-related options and
functions may be hard to find. We may want to put limitations on
what graphics devices are appropriate, specify the maximum size
of the window, etc., and it will be more obvious where to look
for these options if they are divided into their respective
categories.

If we take this approach, we might end up with something like
this:

<pre class="language-cpp">
<code>
Window::SDL win;
Graphics::Vulkan gr;
gr.attach(win);

Game game;
while (game.run()) {
    gr.draw(game);
}
</code>
</pre>

This is only marginally more complicated, a small price to pay
for the benefits it brings.

One challenge here is that there is something of a circular
dependency between a `Graphics::Vulkan` and a `Window`. As
discussed earlier, a `VkInstance` is needed before much of
anything can be done with Vulkan. However, it is hard to do much
with a `VkInstance` until it has a surface to work with, and
creating a surface invariably requires both a `VkInstance` and
a platform window (provided we are going to render to a window
and not to a file or something). So, a little song-and-dance must
be done in which a surfaceless platform window is created along
with a barebones `VkInstance`, following which a surface can be
created from both, at which point the rest of the Vulkan
environment can be set up. This is why `win` and `gr` need to be
initialized separately and then brought together afterwards.

In any case, having one object to represent our platform window
is probably fine. As we said, a platform window is a relatively
simple thing: a `Window` probably holds a handle to the platform
window and some configuration associated with it. However, a
`Graphics` wraps a huge amount of state, whatever API it's
hiding. This only makes sense if we can make lots of assumptions
about how graphics should be configured and operated, such that
any game will function fine with only a small amount of graphics
configuration and very high-level interaction with the graphics
system afterwards. Is this a reasonable expectation?

To answer this question, we can consider two things: what we
might actually do to configure a `Graphics::Vulkan` before the
main loop is run, and what is actually happening in a call to
`Graphics::Vulkan::draw(Game game)`.

### Setting up Vulkan

Compared to OpenGL, a lot needs to happen before any drawing can
be done with Vulkan. This comes with the upside that Vulkan is
more configurable than OpenGL. For instance, error reporting was
baked into OpenGL, meaning it would be checking for errors even
in release builds. Vulkan has a concept of "validation layers"
that can be turned on and off, allowing you to adjust how much
validation is performed; this means you can do extensive
validation in debug builds and turn it all off to save cycles in
release builds, or even give the application user the option to
turn the validations on or off themselves. There are many other
such possibilities during Vulkan setup—but how many do we
actually need to expose in our graphics interface?

Here is, in order, roughly what needs to happen during the
initial setup:

1. A platform window needs to be initialized (just barely). This
   involves setting things like its width and height, title, any
   hints, etc. These should be user-configurable as they will
   vary with different applications.

1. A `VkInstance` needs to be created (just barely). In order
   for this to take place:

   1. The Vulkan environment needs to be queried for the presence
      of all the extensions needed, and those extensions need to
      be enabled if they are found. Extensions are features that
      Vulkan implementations may or may not supply. This includes
      the ability to draw to a window, which is provided through
      the [Window System Integration (WSI)
      extensions](https://github.com/KhronosGroup/Vulkan-Guide/blob/master/chapters/wsi.md),
      so we can't leave this step out. Validations are provided
      via an extension as well, so we need to check for it if we
      want to use them. If we're using a platform abstraction
      library like SDL, it probably has a set of extensions it
      needs to work that we need to check for. The user probably
      doesn't need to have much of a hand in all this specifically;
      they can specify what features they want at a higher level
      and we can check for the necessary extensions behind the
      scenes.

   1. The desired
      [layers](https://vulkan.lunarg.com/doc/sdk/1.2.170.0/linux/layer_configuration.html),
      if any, must be specified and configured. Layers are Vulkan
      components that insert themselves into the call chains of
      Vulkan commands to provide features such as logging,
      tracing, or validations. As with extension checking, the
      user probably doesn't need to know about this specifically
      as long as they can turn these features on or off in
      general.

   1. If debug messages are desired, a debug messenger needs to
      be set up (this is necessary to get messages from the
      validation layers). This requires populating a
      [`VkDebugUtilsMessengerCreateInfoEXT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDebugUtilsMessengerCreateInfoEXT.html)
      struct, which takes a callback function to handle the debug
      messages among other things. All the user should need to
      specify for this is some kind of high-level debug
      config—turning debug messages on or off in general, for the
      graphics system specifically, etc., depending on the
      application.

   At a minimum, we only need to check for the extensions
   required to draw to a window (which may be specified by our
   platform abstraction library) and check for and set up the
   necessary debug features if they are wanted. All the user
   needs to do is pick a window creation strategy and enable the
   desired debug features. Some extensions provide features that
   might be desirable in certain applications, such as the
   ability to bypass the window manager and draw directly to the
   screen (that's
   [`VK_EXT_direct_mode_display`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_EXT_direct_mode_display.html)
   if you're curious); whether or not to go further and support
   these features will depend on what kinds of applications we
   decide to target.

1. The available [physical
   devices](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-physical-device-enumeration)
   need to be enumerated via
   `vkEnumeratePhysicalDevices()` and at least one
   device needs to be chosen out of those available if a suitable
   one can be found. Many applications have minimum requirements
   for the graphics hardware they utilize, and these requirements
   should be specified at this stage.  Also, some applications
   may find a use for multiple devices at once, such as using the
   graphics card to draw to and using the CPU's integrated
   graphics for supplementary calculations. Therefore, the user
   should have the ability to specify how many devices they need
   and what they require from these devices, along with the
   ability to mark requirements as absolutely necessary or merely
   nice-to-have. The results of this should be reported back to
   the user, as they may need to disable certain features or the
   like if their ideal requirements aren't met.

1. At least one [logical
   device](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-devices)
   needs to be generated from any physical devices that need to
   be interacted with. A logical device is an abstract
   representation of a physical device that we can actually send
   drawing commands to, allocate memory with, etc.  In order to
   create a logical device, we need to specify what
   [queues](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-queues)
   we are going to create along with it, using
   [`VkDeviceQueueCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#VkDeviceQueueCreateInfo),
   and the extensions and features of the physical device we need
   to use. (A logical device's queues are what it receives
   commands through; we will retrieve handles to the queue(s) we
   need using
   [`vkGetDeviceQueue()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetDeviceQueue.html)
   along with their logical device.) We also have the option to
   specify a custom memory allocator for the device to use in
   place of the default allocator. What to do for the queues and
   device features should be inferrable from the high-level
   graphics requirements the user describes, so they probably
   don't need to be exposed to the user directly. The custom
   allocator is potentially a different story.

At this point, we are still a ways away from being able to
actually draw to the window. What we do have are the objects that
are likely to survive for the duration of the application's run.
Everything we create after this point may need to be torn down
and recreated periodically, and in some cases may be torn down
and recreated quite often. So, it would be reasonable to look on
these steps as constituting the initialization of a Vulkan
graphics envrionment, with the remaining steps constituting its
"runtime".

Let's consider all the information the user might want to supply
during these steps:

* What windowing strategy to use (native API, a platform
  abstraction library, etc.)
* The dimensions, title, hints, etc. of the platform window
* What graphics debug features should be enabled if any
* Minimum and nice-to-have requirements of the graphics hardware
* More esoteric stuff like custom allocators, multiple physical
  and/or logical devices, a compute pipeline setup, etc.

Excepting the more esoteric features, this information seems
logical to supply in essentially three steps. The user can pick a
windowing strategy based on what windowing interface object they
choose to instantiate, and they can supply information about the
sort of window they want during its instantiation. The debug
features and other high-level (i.e. extension-level) requirements
need to be supplied during `VkInstance` creation, so those
would be reasonable to provide during initialization of the
graphics object. When specifying requirements for physical device
characteristics, the user will want feedback about what sort of
device has been selected and how well it actually fits their
requirements; this implies that this step should be done
separately from initializating the graphics object.

These leads us to the following:

<pre class="language-cpp">
<code>
SDLWindow win {settings};
VulkanGraphics gr {features, debug_lvl};
gr.attach(win);
gr.pick_device(requirements);

Game game;
while (game.run()) {
    gr.draw(game);
}
</pre>
</code>

This seems reasonable as far as setup goes. What about
`gr.draw(game)`?

### Runtime

What's actually happening when a `Game` is being drawn? (This
presumes a design where `Game` consists of abstract data and
behavior and has only a high-level understanding of the graphics
system at best, such that the graphics object will be treating it
like a large data structure). Considering this will let us know
if we can present as simple an interface as
`VulkanGraphics::draw` or if we may want something more
complicated.

Of course, if we really are treating `Game` as nothing but data
during the `draw` call, we can think of a `Game` as a giant set
of parameters to `draw`. This implies that `draw` may indeed be a
simple enough interface at this level of the program regardless
of how involved and variable the behavior of `draw` is. The
viability of this approach naturally depends on the design of
`Game`.

In any case, let's consider what may need to happen during a
`draw` call:

1. For creation, storage, and manipulation of image data, we will
   need to work with
   [`VkImage`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#resources-images)s,
   which are 1–3-dimensional formatted data sets stored in device
   memory that are well-suited to capturing visual information.
   `VkImage`s can be created via
   [`vkCreateImage()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateImage.html),
   which takes a
   [`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html),
   but there are also other ways of creating them; for example,
   creating a swapchain (see below) creates a set of `VkImage`s
   implicitly, which can be accessed via
   [`vkGetSwapchainImagesKHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetSwapchainImagesKHR.html).
   A `VkImage` is composed of
   [texels](https://developer.mozilla.org/en-US/docs/Glossary/Texel),
   which are short sequences of bits that often describe color
   information but can also be used for other purposes. The
   structure of a `VkImage`'s texel data is described by its
   [`VkFormat`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormat.html).

   `VkImage`s do not necessarily consist of a single cohesive
   set of texels of specific height and width. For example, they
   can store mipmaps, and can function as an array of sets of
   texel data by storing data in multiple layers. As such, Vulkan
   has the concept of an "image subresource," which is a specific
   mipmap level and layer of an image—in other words, a single
   cohesive set of texels. It also has the concept of an "image
   subresource range," which is a set of image subresources of
   contiguous mipmap levels and layers.

1. A [WSI
   swapchain](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#_wsi_swapchain),
   represented by
   [`VkSwapchainKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSwapchainKHR.html)
   and created via
   [`vkCreateSwapchainKHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateSwapchainKHR.html)
   using a
   [`VkSwapchainCreateInfoKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSwapchainCreateInfoKHR.html),
   is needed to actually draw to a window surface. This is
   basically a collection of
   [`VkImage`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#resources-images)s
   that is associated with a specific surface. In order to draw
   to an image, the application requests an image from the
   swapchain, queues up a set of drawing commands on a logical
   device queue, and then presents the image to the queue for
   processing.  Swapchains facilitate synchronization with the
   refresh rate of the display, and can be used to implement
   techniques like double and triple buffering.

   A swapchain will need to be set up at least once, but can be
   long-lived under some circumstances.  However, because it is
   associated with a surface, it needs to be reconstructed if the
   surface changes, such as during a window resize. This implies
   that the graphics object needs to keep track of its associated
   window somehow in order to query it for changes during a
   `draw` call, although the user probably doesn't need to be
   aware of this.

1. To actually make use of the `VkImage`s in the swapchain, we
   need to create
   [`VkImageView`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#resources-image-views)s
   to them. These are essentially objects that describe how the
   images should be treated during rendering, such as the image's
   dimensions, the subset of the image that should be rendered,
   the subresource range to make available, etc. This obviously
   depends closely on what the image actually is, and can
   probably be determined based on that without direct user
   input.

1. In order to create a video frame, we need a
   [`VkRenderPass`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPass.html),
   which represents the high-level structure of the frame—what
   images will be drawn to it, how they should be processed,
   where they can be found, etc. In more precise terms, a render
   pass is a description of the relationships between and among
   two different things: attachments and subpasses.

   Attachments are like containers or slots for images (in the
   `VkImage` sense) that can contain things like color,
   stencil, or depth information. They are defined via
   [`VkAttachmentDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html)
   (or the more recent
   [`VkAttachmentDescription2`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription2.html)
   which is designed to be extensible; many of the objects
   associated with render passes have variants like this). Aside
   from storing references to them directly, there is also a
   special structure
   [`VkAttachmentReference`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentReference.html)
   that objects which need to make use of an attachment can store
   as a kind of placeholder. This allows them to express what
   type of attachment they require without having to bind tightly
   to a specific attachment.

   A subpass is expressed mainly through two struct types in
   tandem.
   One is
   [`VkSubpassDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDescription.html),
   a collection of `VkAttachmentReference`s associated with one of
   the pipeline types. The other is
   [`VkSubpassDependency`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDependency.html),
   which describes dependent relationships between subpasses for
   the sake of synchronization as well as the pipeline stages the
   subpasses need access to. Together, they describe a certain
   phase of a rendering process, apart from the actual
   instructions to be executed by the GPU during that phase.

   Attachments and subpasses are brought together in a
   [`VkRenderPassCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPassCreateInfo.html).
   This structure stores a list of `VkAttachmentDescription`s, a
   list of `VkSubpassDescription`s, and a list of
   `VkSubpassDependency`s, which formally describes the render
   pass. It can be passed to
   [`VkCreateRenderPass`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateRenderPass.html)
   to produce a `VkRenderPass`.

1. In order to make use of a render pass, we also need a
   framebuffer for it to work with, which in the context of
   Vulkan is a collection of specific attachments in memory
   represented by `VkImageView`s. A framebuffer is represented
   by a
   [`VkFrameBuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFramebuffer.html)
   handle, which is created via
   [`vkCreateFramebuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateFramebuffer.html)
   using a
   [`VkFramebufferCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFramebufferCreateInfo.html).
   It is associated with a specific `VkRenderPass`, and in
   addition to holding onto a list of `VkImageViews` it also
   has its own parameters for width, height, and number of
   layers. The number of layers must be equal to or less than the
   `arrayLayers` property of the `VkImage`s.

1. We also need
   [`VkPipeline`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipeline.html)s,
   which represent a set of operations for the GPU to perform
   (this is where you actually attach your shaders, using
   [`VkShaderModule`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkShaderModule.html)s).
   They come in three flavors: *graphics*, *compute*, and *ray
   tracing*. See below for more information on pipelines.

1. The last major piece of machinery we need is a way to tell the
   graphics hardware to actually make use of everything we've set
   up. This is via command buffers; see below.

## Queues

In order to actually do work on a device with Vulkan, commands
need to be submitted to it. These commands are submitted through
Vulkan objects called _queues_.

The reason it is done this way, rather than calling commands on
the device directly, is mainly a matter of performance. For one,
sending a command to a device is an expensive operation and
should be kept to a minimum; this approach allows many commands
to be prepared in advance and then submitted to the device all at
once. Also, this approach increases opportunities for
concurrency: commands may run simultaneously unless explicltly
synchronized (see "Synchronization," below). Because of the
highly parallel nature of graphics devices, this is a more
reasonable default than having the host call commands
sequentially.

When creating a logical device, queues are made for it at the
same time as the device itself. The queues to make are specified
via
[`VkDeviceQueueCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceQueueCreateInfo.html);
[`VkDeviceCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceCreateInfo.html)
has a parameter `pQueueCreateInfos` which holds an array of
`VkDeviceQueueCreateInfo`s. The queues that can be created depend
on the properties of the physical device.

Once the logical device has been created, you can retrieve
handles to any of its queues via
[`vkGetDeviceQueue()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetDeviceQueue.html)
(or
[`vkGetDeviceQueue2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetDeviceQueue2.html),
if you want to retrieve a handle to a queue created with specific
[`VkDeviceQueueCreateFlags`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceQueueCreateFlags.html)).

Work is submitted to a queue via queue submission commands such
as
[`vkQueueSubmit2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit2KHR.html)
or
[`vkQueueSubmit()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit.html).
A queue submission command takes a target queue, a set of
_batches_ of work, and optionally a fence to signal on completion
(see "Fences" under "Synchronization"). Each batch (described by
e.g.
[`VkSubmitInfo2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubmitInfo2KHR.html))
consists of zero or more semaphores to wait on before starting,
zero or more work items to execute (in the form of command
buffers), and zero or more semaphores to signal afterwards (see
"Semaphores" under "Synchronization").

Queues are destroyed along with the logical device they were
created with when `VkDestroyDevice` is called on the device in
question.

## Command buffers

Command buffers, represented by
[`VkCommandBuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandBuffer.html),
are used to submit commands to a device queue. They are
allocated using
[`vkAllocateCommandBuffers()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateCommandBuffers.html),
which requires specifying a device, a _command pool_, and the
_level_ of the buffers to be allocated. Rather than execute
commands immediately, commands are _recorded_ onto command
buffers to be later submitted to a device queue, which allows
command buffers to be set up concurrently with rendering
operations.

A _command pool_, represented by
[`VkCommandPool`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandPool.html),
is an opaque object used to allocate memory for command
buffers on a device. They can be _reset_ using
[`vkResetCommandPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkResetCommandPool.html),
which reinitializes all the command buffers alocated from the
pool and return the resources they were using back to the
pool. A command pool can also be _trimmed_ using
[`vkTrimCommandPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkTrimCommandPoolKHR.html),
which frees up any unused memory from the pool without
affecting the command buffers allocated from it; this is
useful to e.g. reclaim memory from a specific command buffer
that has been reset without needing to reset the whole pool.

Every command buffer has a level, which is either _primary_ or
_secondary_. A primary command buffer can be submitted to a
device queue, and can also execute secondary command buffers.
Neither of these things is true of secondary command buffers.
However, secondary command buffers can inherit state from
primary command buffers by using
[`VkCommandBufferInheritanceInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandBufferInheritanceInfo.html)
and setting
[`VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandBufferUsageFlagBits.html)
when calling
[`vkBeginCommandBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkBeginCommandBuffer.html).
This allows secondary command buffers to be recorded
concurrently after the primary command buffer which is going
to execute them has been set up, and also allows a secondary
command buffer to be recycled for use with different primary
command buffers. See
[here](https://github.com/KhronosGroup/Vulkan-Samples/blob/master/samples/performance/command_buffer_usage/command_buffer_usage_tutorial.md)
for more on this.

Command buffers can execute a wide variety of commands. They
are all specified with functions that follow the naming format
`VkCmd*`. Among other things, they allow for copying images
and buffers, starting and managing render passes and
subpasses, binding resources like pipelines and buffers to the
command buffer, and making draw calls on the associated device.

Command buffers pass through a number of different states.
When first allocated they are in the _initial_ state. From
here, they can either be freed with
[`vkFreeCommandBuffers()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkFreeCommandBuffers.html)
or be put into the _recording_ state via
[`vkBeginCommandBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkBeginCommandBuffer.html).
While in the recording state, `VkCmd*` functions can be used
to record commands to the buffer, or it can be reset back to
the initial state with
[`vkResetCommandBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkResetCommandBuffer.html).
Afterwards, calling
[`vkEndCommandBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkEndCommandBuffer.html)
puts it into the _executable_ state; from here, it can be submitted
to a queue with
[`vkQueueSubmit2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit2KHR.html)
or
[`vkQueueSubmit()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit.html)
if it's a primary buffer, recorded to a primary buffer with
[`vkCmdExecuteCommands()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdExecuteCommands.html)
if it's a secondary buffer, or reset. Once submitted to a
queue, it enters the _pending_ state, during which the
application must not modify it in any way. Once executed, it
either re-enters the executable state or enters the _invalid_
state if it was recorded with
[`VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandBufferUsageFlagBits.html)
It can also enter the invalid state through other means, such
as if a resource used in one of its commands is modified or
deleted. When in the invalid state, it can only be freed or
reset.

In order to detect when a command buffer has left the pending
state, a synchronization command should be used.

## Synchronization

Execution of commands is highly concurrent, and ordering of
commands has few guarantees (see [7.2 Implicit Synchronization
Guarantees](https://www.khronos.org/registry/vulkan/specs/1.2-khr-extensions/html/chap7.html#synchronization-implicit)
in the spec for the specifics). Therefore, command invocations
and the flow and storage of data in the application must be
explicitly synchronized in many cases. Vulkan provides several
mechanisms for this purpose.

### Scopes and dependencies

Speaking in general, we can speak of _operations_ as a generic
unit of work to be carried out through Vulkan. A
synchronization command is only able to create dependencies
between certain categories of operations. The set of
operations a synchronization command can create dependencies
between are called its _synchronization scopes_.

If a synchronization command **S** has synchronization scopes
**S₁** and **S₂**, and is submitted just after a set of
operations **A** and just before a set of operations **B**, it
creates a dependency between the operations in **A∩S₁** and those
in **B∩S₂**. Any other operations are not synchronized.  This
allows synchronization to be specified quite precisely, but also
means that care must be taken to ensure that operations that need
to be synchronous are actually run that way. The synchronization
scopes utilized should be as narrow as possible, as this will
maximize opportunities for concurrent execution and caching by
the implementation.

In general, dependencies created this way are referred to as
_execution dependencies_. However, there is a special type of
execution dependency that is important enough to consider on
its own. These are _memory dependencies_, which are used to
synchronize memory access. They are the most common type of
execution dependency encoutered in Vulkan.

Some operations read from or write to locations in memory.
Execution dependencies that are not memory dependencies cannot
guarantee that data which has been written by an operation
will be ready for reading by a later operation, or that one
set of data will be written to a location before another set
of data is written there. Memory dependencies between two
operations guarantee that the first operation will finish
writing before the location it's writing to is made
_available_ to later operations, and that the data is made
_visible_ to the second operation before it begins. An
available value stays available until its location is written
to again or freed; if an available value becomes visible to a
type of memory access, it can then be read from or written to
by memory accesses of that type as long as it stays available.

To be more precise, a synchronization command that involves a
memory dependency has _access scopes_. These are derived from its
synchronization scopes. If such a command has synchronization
scopes **S₁** and **S₂**, its access scope **Sm₁** consists of
all the memory accesses performed by the commands in **S₁**, and
likewise for **Sm₂** and **S₂**. Then if **Am** is the set of
memory accesses performed in **A**, and **Bm** is likewise for
**B**, submitting **A**, **S**, and **B** for execution in that
order will mean that memory writes in **Am∩Sm₁** will be made
available, and that available memory writes in **Am∩Sm₁** will be
made visible to **Bm∩Sm₂**.

### The device and the host

Synchronization can be necessary

### Mechanisms

Earlier we said that Vulkan provides several mechanisms for
synchronization. To be specific, there are five: _semaphores_,
_fences_, _events_, _pipeline barriers_, and _render passes_. One
of these—render passes—we have already explored briefly, but we
will explore it in depth here. The others are new to us.

Before we get into the details, here's a brief description of
when you might want to use each:

 * **Semaphores**:

### Semaphores

Semaphores have become the "all-purpose" synchronization
primitive of Vulkan, and can be used for synchronization between
batches as well as the host. This makes them a good choice for
many of an application's synchronization needs. However, this has
also made them a complex topic. As such, we will discuss them in
the abstract first in order to get our bearings, and then discuss
how to code with them afterwards.

A semaphore is a kind of stateful object. It can be _signaled_,
which changes its state in a well-defined way. There are various
ways a semaphore can become signaled, and also various ways to
check the state of a semaphore from elsewhere, including ways to
wait until the state of a semaphore takes on a certain value.

As of Vulkan 1.2, semaphores come in two types, _binary_ and
_timeline_. Earlier versions have only binary semaphores in their
core APIs, but Vulkan 1.0 and up can support timeline semaphores via
the extension
[`VK_KHR_timeline_semaphore`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_timeline_semaphore.html).

Binary semaphores have two states: signaled and unsignaled. When
a binary semaphore begins to be waited on, it becomes unsignaled;
it can then be signaled from elsewhere, after which the wait
operation will finish. This property means that waiting and
signalling operations on binary semaphores need to be carefully
synchronized themselves to prevent hazards.

The state of a timeline semaphore is defined by a 64-bit unsigned
integer. The value of this integer is under the control of the
application, with the caveat that it must be strictly increasing,
so an application should not set it to a lower value than it
currently has. A signalling operation on a timeline semaphore
changes its state to a new value defined by the signalling
operation. A wait operation on a timeline semaphore waits for its
state to become equal to or greater than a certain value defined
by the wait operation.

These properties allow a single timeline semaphore to track and
appropriately synchronize the progress of an application through
a complex chain of batches.  For this reason, the Khronos Group
[recommends](https://www.khronos.org/blog/vulkan-timeline-semaphores)
that timeline semaphores be used "for all coarse-grained
synchronization purposes" when possible as a single timeline
semaphore can replace several binary semaphores and/or fences,
thereby reducing complexity and improving performance.

#### Scopes

When a batch is submitted to a queue that includes a semaphore to
be signaled, it defines a _semaphore signal operation_ within the
batch that puts the semaphore into a signaled state. This
operation's first synchronization scope includes every other
command submitted in the batch, unless it is limited to specific
pipeline stages, in which case it includes only those commands
that run during these stages. Also, it often includes everything
defined earlier than the operation in the submission order, and
any semaphore or fence signal operations that occur before it in
the signal operation order. A more precise discussion will follow
shortly. As a general rule, it is reasonable to think of a
semaphore signal operation as coming at the end of a batch unless
otherwise specified.

In any case, a semaphore signal operation's second
synchronization scope includes only itself. Its first access
scope includes all the memory accesses performed by the device in
its first synchronization scope, and its second access scope is
empty.

When a batch is submitted to a queue that includes a semaphore
to be waited on, it defines a _semaphore wait operation_ in the
batch.

This operation's first synchronization scope includes all
the semaphore signal operations that operate on every semaphore
waited on in the batch and that occur before the wait operation
completes. In other words, the rest of the batch will not be
carried out until all the semaphore wait operations finish.

A semaphore wait operation's second synchronization scope
includes every command submitted in the batch, unless this scope
has been limited to specific pipeline stages, in which case it
includes only those commands which happen during these stages. In
most cases it also includes all the commands that occur later in
the submission order. We will discuss this in precise terms
shortly.

In any case, a semaphore wait operation's first access
scope is empty, and its second access scope includes all the
memory accesses performed by the device in the block.

For binary semaphores, the semaphore's wait operation will be
carried to completion once its signal operation finishes. It will
be set to unsignaled at the beginning of its wait operation,
implying that binary wait and signal operations should occur in
carefully-managed 1:1 pairs. Execution dependencies can be used
for this purpose.

For timeline semaphores, the semaphore's wait operation will be
carried to completion once the semaphore's payload is equal to or
greater than an application-specified value declared when the
semaphore is submitted. This process is free from the limitations
of waiting on binary semaphores.

#### The API

A recent extension to Vulkan,
[`VK_KHR_synchronization2`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_synchronization2.html),
makes significant changes to the semaphore API (as well as other
things). We will look at how to work both with this extension as
well as the core API. The Khronos Group [encourages the use of
this
extension](https://www.khronos.org/blog/vulkan-sdk-offers-developers-a-smooth-transition-path-to-synchronization2)
and intends for it to be easier to work with than the older APIs.

##### Creation and destruction

The only context needed to create and destroy semaphores is a
device.

Semaphores are created via
[`vkCreateSemaphore()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateSemaphore.html).
By default, this creates a binary semaphore in the unsignaled
state. However, a timeline semaphore can be created by adding a
[`VkSemaphoreTypeCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSemaphoreTypeCreateInfo.html)
to the `pNext` chain of the
[`VkSemaphoreCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSemaphoreCreateInfo.html),
setting its `semaphoreType` field to
`VK_SEMAPHORE_TYPE_TIMELINE`, and supplying the initial value of
the semaphore state in its `initialValue` field.

Semaphores are destroyed via
[`vkDestroySemaphore()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroySemaphore.html).
Any submitted batches which refer to a semaphore must have
finished execution before this is called on it.

##### Queue submission

Semaphores can be submitted to a queue as part of a batch. As
described, this can produce a semaphore wait operation or
semaphore signal operation in the batch. The
way to do this depends on whether you are using the
`synchronization2` feature or not.

If you are, you can use
[`vkQueueSubmit2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit2KHR.html).
This takes an array of
[`VkSubmitInfo2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubmitInfo2KHR.html),
which includes fields `pWaitSemaphoreInfos[]` and
`pSignalSemaphoreInfos[]`. These point to arrays of
[`VkSemaphoreSubmitInfoKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSemaphoreSubmitInfoKHR.html),
which most significantly takes a handle to a semaphore, the value
to signal with or wait on if the semaphore is a timeline
semaphore, and a bitmask of
[`VkPipelineStageFlagBits2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineStageFlagBits2KHR.html)
flags to restrict the semaphore's scopes to specific pipeline
stages. This method of submission also takes into account the
submission order of commands submitted to the queue, in terms of
the semaphore's scopes.

If you are not using `synchronization2`, you can instead use
[`vkQueueSubmit()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit.html).
This takes an array of
[`VkSubmitInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubmitInfo.html),
which includes two arrays of semaphore handles, `pWaitSemaphores`
and `pSignalSemaphores`. These indicate the semaphores to wait on and
signal in the batch, respectively. There is also an array
`pWaitDstStageMask[]` of
[`VkPipelineStageFlags`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineStageFlags.html),
which restricts the scopes of the corresponding semaphore wait
operations to specific pipeline stages. If using timeline
semaphores, you can add a
[`VkTimelineSemaphoreSubmitInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkTimelineSemaphoreSubmitInfo.html)
to the `pNext` chain of your `VkSubmitInfo`, which allows you
to specify values for the wait and signal operations on the
respective semaphores (binary semaphores can have values of 0 set
here as they are ignored). As with `VkQueueSubmit2KHR`, this
takes submission order into account in scope terms for the
semaphores in question.

You can also use other
[queue submission
commands](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-submission)
such as 
[`vkQueueBindSparse()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueBindSparse.html).
See the relevant documentation for more details.

##### Host operations

The host can wait on or signal timeline semaphores directly. None
of these operations work with binary semaphores.

The host can query the value of a timeline
semaphore's state via
[`vkGetSemaphoreCounterValue()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetSemaphoreCounterValue.html).
This takes device and semaphore handles and a pointer to a
`uint64_t` which will receive the value. Note that if there is a
pending queue submission command that involves the semaphore, it
may change the semaphore's state very shortly after this is
called, so take care in its use.

The host can wait on a set of semaphores to reach particular
state values using
[`vkWaitSemaphores()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkWaitSemaphores.html).
This takes a
[`VkSemaphoreWaitInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSemaphoreWaitInfo.html),
which in turn takes a pointer into an array of semaphore handles,
a pointer into an array of values to wait on (one for each
corresponding semaphore). It also allows a timeout period to be
specified in nanoseconds (although nanosecond precision is not
guaranteed), and a flag to specify if it should wait for any of
the semaphores to reach its corresponding value or if it should
wait on all of them (the latter being the default).

When `vkWaitSemaphores()` is called, it returns immediately if
its wait condition is met or if its timeout period is set to 0.
Otherwise, it blocks until the condition is met or until the
timeout period has elapsed, whichever is sooner.

The host can signal a semaphore using
[`vkSignalSemaphore()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkSignalSemaphore.html).
This takes a
[`VkSemaphoreSignalInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSemaphoreSignalInfo.html),
which allows you to specify a semaphore and a value to set its
state to upon signalling. The signalling operation produced is
executed immediately, and its first synchronization scope
includes the execution of `vkSignalSemaphore()` as well as
anything that has happened prior to it.

### Fences

Fences are a way to create a dependency from within a queue to
the host. They date to before the introduction of timeline
semaphores, and in most cases a timeline semaphore may be more
elegant to use. They can be _signaled_ as part of the execution of a
queue submission command like `vkQueueSubmit2KHR()`. From the
host, they can be read via
[`vkGetFenceStatus()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetFenceStatus.html),
waited on via
[`vkWaitForFences()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkWaitForFences.html),
and unsignaled via
[`vkResetFences()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkResetFences.html).
They are created with
[`vkCreateFence()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateFence.html),
and require a device to create the fence with and a specification
of whether the fence should be initialized in the signaled or
unsignaled state. They are destroyed with
[`vkDestroyFence()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyFence.html).

When a fence is submitted to a queue, it defines a _fence signal
operation_. It's generally safe to think of a fence signal
operation as making everything in the queue wrap up before the
fence is signaled. To be precise, the first synchronization scope
of a fence signal operation includes all the operations in the
current queue submission command, every command that occurs
earlier in the submission order if applicable, and any fence and
semaphore signal operations that occur earlier in the signal
operation order. The fence signal operations's second
synchronization scope includes only itself. Its first access
scope includes all the memory accesses in its first
synchronization scope, and its second access scope is empty.

Of note, waiting on a fence does not guarantee that the results
of the accesses in its first access scope will be visible to the
host after the fence is signaled, as a fence's access scopes only
apply to device accesses. A _memory barrier_ must be used to
ensure this (see below).

<!--
Vulkan provides mechanisms for interprocess signalling via fences.
See
[`VkExportFenceCreateinfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkExportFenceCreateInfo.html)
and [7.3.2 Importing Fence Payloads](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#synchronization-fences-importing) for more on this.
-->

### Events

Events are a fine-grained synchronization mechanism—they can be
used to create a dependency between two commands in the same
queue, or between the host and a queue. However, they are not
intended for use between queues. They have two states, signaled
and unsignaled. They support signalling on the device or the
host, waiting on the device, and querying from the host.

Events are created via
[`vkCreateEvent()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateEvent.html).
This requires a device, and allows the caller to specify if the
event will be managed from the device only (i.e. no host event
commands will be used with it). They are destroyed via
[`vkDestroyEvent()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyEvent.html),
which requires the same device used to create the event.

#### Device operations

##### With `synchronization2`

Events can be set to be signaled on the device as part of batch
execution with
[`vkCmdSetEvent2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdSetEvent2KHR.html).
This takes a pointer to a
[`VkDependencyInfoKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDependencyInfoKHR.html),
which allows the caller to use arrays of
[`VkMemoryBarrier2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkMemoryBarrier2KHR.html),
[`VkBufferMemoryBarrier2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBufferMemoryBarrier2KHR.html),
and
[`VkImageMemoryBarrier2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageMemoryBarrier2KHR.html)
to specify the first synchronization and access scopes of the
signaling operation (i.e. using the `src*` fields of these
structures). Its second synchronization scope includes itself.
Its second synchronization scope as well as its second access
scope also include any queue family ownership transfers or image
layout transitions defined in the `VkDependencyInfoKHR`.

Events can be waited on as part of batch execution with
[`vkCmdWaitEvents2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdWaitEvents2KHR.html)
This takes an array of events and a matching array of
`VkDependencyInfoKHR`s. The `VkDependencyInfoKHR`s are used
to define the second synchronization and access scopes of the
wait operation (i.e. using the `dst*` fields of its memory
barrier structures). If the first synchronization scope of an
events included in this operation contains any device operations,
it should have had a corresponding signal operation defined for
it earlier in the submission order on the same queue, and the
`VkDependencyInfoKHR` supplied for it should exactly match that
used there. These conditions do not apply if its first
synchronization scope includes only host operations and
`VK_EVENT_CREATE_DEVICE_ONLY_BIT_KHR` was not set during its
creation.

##### Without `synchronization2`

Events can be set to be signaled during queue execution with
[`vkCmdSetEvent()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdSetEvent.html).
This works identically to `VkCmdSetEvent2KHR` except that it
does not define an access scope. Its first synchronization scope
is specified via a `VkPipelineStageFlags`.

Events can be waited on during queue execution with
[`vkCmdWaitEvents()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdWaitEvents.html).
This works similarly to `VkCmdWaitEvents2KHR`, but defines the
first access scope for every signal operation waited on in
addition to its own scopes. Speaking roughly, signal operations
on the same queue are included in the first synchronization scope
of the wait operation if they occur earlier in the pipeline.
Speaking precisely, event signal operations on the same queue are
included in the wait operation's first synchronization scope if
they were earlier in the submission order and the logically
latest pipeline stage of the `stageMask` used when defining the
signal operation is logically earlier than or equal to the
logically latest pipeline stage in the `srcStageMask` used when
defining the wait operation. The wait operation's second
synchronization scope includes all the commands that occur later
in the submission order, limited by the pipeline stages specified
in `dstStageMask`. Its first access scope is defined by the
intersection of accesses in the pipeline stages of its source
stage mask and the scopes defined by its memory barriers. Its
second access scope is defined likewise for its destination stage
mask.

#### Host operations

The host can query the status of an event via
[`vkGetEventStatus()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetEventStatus.html).
Note that if the event is involved in a pending batch the result
of this operation may be out-of-date.

The host can signal an event via
[`vkSetEvent()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkSetEvent.html),
and can unsignal an event via
[`vkResetEvent()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkResetEvent.html).
These immediately defines and executes an event signal/unsignal
operation for the event, unless the event is already
signaled/unsignaled, in which case nothing happens. Note that
there must be an execution dependency between an unsignal
operation and any wait operations scheduled for the event in
question.

Host interaction with an event should not be done from more than
one thread at a time, and potentially simultaneous interactions
should be separated with a memory barrier.

### Pipeline barriers

Pipeline barriers are similar to events in that they provide a
mechanism for synchronizing the execution of commands within a
queue. However, they do not have internal state; they merely
create a dependency between commands that come before and after
them in the submission order.

#### Recording

If using `synchronization2`, you can record a pipeline barrier
via
[`vkCmdPipelineBarrier2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdPipelineBarrier2KHR.html).
This takes a pointer to a `VkDependencyInfoKHR` like the
queue-based event commands do. The first synchronization and
access scopes of the dependencies described in this structure are
applied to any commands submitted earlier, and the second
synchronization and access scopes are applied to any commands
submitted later.

If not using `synchronization2`, you can record a pipeline
barrier via
[`vkCmdPipelineBarrier()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdPipelineBarrier.html).
This is similar to `vkCmdPipelineBarrier2KHR()` except that the
memory barriers are passed as arguments separately instead of
within a `VkDependencyInfoKHR`.

#### Use within a render pass

If a pipeline barrier command is recorded within a render pass
instance, several special conditions apply. For one, the command
only applies to operations within the same subpass. Also, the
render pass needs to declare a _self-dependency_ for the
subpass—that is to say, it should have a subpass dependency where
`srcSubpass` and `dstSubpass` are both set to that subpass's
index.

These self-dependencies come with their own requirements. Their
pipeline stage bits must only encompass graphics pipeline stages.
If any of the stages in `srcStages` are framebuffer-space stages,
`dstStages` must only contain framebuffer-space stages. If they
do both contain framebuffer-space stages, `dependencyFlags` must
include `VK_DEPENDENCY_BY_REGION_BIT`, and if the subpass has
more than one view, it must include
`VK_DEPENDENCY_VIEW_LOCAL_BIT` as well. If the self-dependency
has either of these bits set, the pipeline barrier must have them
set also.

Pipeline barriers within a render pass instance should not
include buffer memory barriers. Image memory barriers can be
used, but only for image subresources used as attachments within
the subpass, and they must not define an image layout
transition or queue family ownership transfer.

### Memory barriers

These are not synchronization primitives in and of themselves,
but rather data structures which are used to define access
dependencies for images and buffers. We have already seen them in
the context of defining events and pipeline barriers, but they
have some properties we have not yet explored.

Memory barriers come in three types. Global memory barriers such
as `VkMemoryBarrier2KHR` encompass all the memory accesses in
their specified pipeline stages. Buffer and image memory barriers
such as `VkBufferMemoryBarrier2KHR` and
`VkImageMemoryBarrier2KHR` apply to specific, single buffer and
image resources respectively.

#### Queue family ownership transfer

Buffer and image memory barriers can be used to declare a _queue
family ownership transfer_ for the resource they relate to. If
this resource was created with a
[`VkSharingMode`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSharingMode.html)
of `VK_SHARING_MODE_EXCLUSIVE`, the first queue family in which
it is used acquires the exclusive use of it, and this _ownership_
must be explicitly transferred to another queue family in order
for it to be accessible there.

This is only necessary if the receiving queue family needs the
contents of the resource to remain valid. Also, it is not
necessary if the resource was declared with a sharing mode of
`VK_SHARING_MODE_CONCURRENT`, which allows it to be accessed
concurrently from multiple queue families. However,
`VK_SHARING_MODE_EXCLUSIVE` may offer better access performance.

Two operations are involved in a queue family ownership transfer,
a _release operation_ and an _acquire operation_. These must
occur in that order. An execution dependency should be used to
ensure this, such as that introduced by a semaphore.

To define a release operation, execute a buffer or image memory
barrier on a queue from the source family using
`VkCmdPipelineBarrier` (and possibly
`VkCmdPipelineBarrier2KHR`; see
[here](https://github.com/KhronosGroup/Vulkan-Docs/issues/1516)).
To define an acquire operation, perform the same procedure on a
queue from the destination family. In both cases, the
`srcQueueFamilyIndex` and the `dstQueueFamilyIndex` parameters of
the memory barrier instances should match those of the source and
destination families. Their destination and source access masks
should be set to 0.

If an image memory barrier is used and an image layout transition
is desired (see below), the values of `oldLayout` and `newLayout`
used in the release and acquire barriers should match. A layout
transition specified in this way will only happen once. It will
occur after the release operation but before the acquire
operation.
Any writes to the memory bound to the resource in question must be made available before 

Any writes to the memory bound to the resource in question must
be made available before the queue family ownership transfer is
carried out. Memory that is available will automatically be made
visible to the release and acquire operations, and any writes
performed by these operations will in turn be made available.

#### Image layout transition

Image subresources can be transitioned from one layout to
another as part of a memory dependency, such as that introduced
by an image memory barrier. The operation to do this always
operates on a specific image subresource range and includes a
specification of both the old layout and the new layout.

In order for the image contents to be preserved, the old layout
specified must match that of the image prior to the transition.
Otherwise, it must be set to `VK_IMAGE_LAYOUT_UNDEFINED`, in
which case the contents may be discarded.

The memory bound to an image subresource range must be made
available prior to an image layout transition operation on it, as
such an operation may read and write to this memory. If the
memory is available, it will automatically be made visible to the
operation, and writes performed by the operation will
automatically be made available. Because of this requirement, it
is important to ensure that any operations which need to access
this memory before the layout transition are made to finish
beforehand through the use of an approriate memory barrier, and
that operations which need to access it afterwards are handled
likewise.

## Pipelines

As we said earlier, Vulkan pipelines represent a set of
operations for the GPU to perform, and they come in three flavors.
They are where you attach your shaders, and where you configure
the interactions between shader invocations.

### Graphics pipeline

A graphics pipeline, created through
[`vkCreateGraphicsPipelines()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateGraphicsPipelines.html),
is meant primarily for the production of visual imagery. It can:

* take a set of vertices ("draw")
* assemble them into geometric primitives ("input assembler")
* apply transformations to them ("vertex shader")
* compute a tesselation of them ("tesselation
  {control,primitive,evaluation} shader")
* generate other geometry from them ("geometry shader")
* save the processed vertices into a buffer ("transform
  feedback")
* swizzle the clip coordinates of primitives sent to a given
  viewport ("viewport swizzle") ("Swizzling", in the context of
  computer graphics, is the act of creating new vectors from an
  arbitrary combination and rearrangement of the components of
  other vectors. For instance, if a vector `A = {1,2,3,4}`, a
  vector `B` could be produced by swizzling `A` such that `B =
  A.wwxy = {4,4,1,2}`. See [the Wikipedia
  article](https://en.wikipedia.org/wiki/Swizzling_\(computer_graphics\))
  for more. Viewport swizzle can be used to efficiently render a
  skybox from a cubemap texture, for instance.)
* assign each vertex of a primitive the same value for a given
  vertex output attribute ("flat shading")
* cull and clip primitives in accordance with given cull and view
  volumes ("primitive clipping")
* perform interpolation of output attribute values for points
  produced by clipping ("clipping shader outputs")
* scale the **W** component of clip coordinates relative to a
  viewport based on given coefficients ("controlling viewport
  __W__ scaling")
* divide the components of a vertex in *clip coordinates* by its
  __W__ component to yield its *normalized device coordinates*,
  which can then be transformed in accordance with a viewport
  ("coordinate transformations")
* rotate the post-vertex-shading clip coordinates in the XY plane
  by multiples of 90 degrees for a given render pass instance, as
  if the whole swapchain image was rotated between rendering and
  presentation ("render pass transform")
* transform vertex coordinates in relation to a viewport to
  prepare them for rasterization, i.e. put them in *window space*
  ("controlling the viewport")
* determine whether polygon primitives are front- or back-facing,
  in order to cull them if they appear to be invisible to the
  viewer ("basic polygon rasterization")
* take geometry in window space and compute *fragments* from it,
  which are discretized representations of the geometry
  appropriate for calculating pixel values from ("rasterization")
* perform tests on the fragments, such as how far away they are
  from the viewport, whether they are inside a certain portion of
  the viwport, whether they are covered by another fragment,
  etc., which can be used for e.g. occlusion culling
  ("per-fragment tests")
* color the fragments using data attached to the vertices they
  were computed from ("fragment shader")
* blend the colors of the fragments with the colors of the
  samples at the same location on the framebuffer they are going
  to be drawn to ("blending").

It can be run in two modes: *primitive shading* or *mesh
shading*. In primitive shading mode, geometric primitives are
computed from the input vertices in accordance with a relatively
automatic but well-defined and configurable process. In mesh
shading mode, primitives are generated by a user-supplied mesh
shader and passed directly from there to the rasterizer, which
(among other things) allows primitives to be culled much earlier
in the pipeline. Mesh shading is only available on recent,
high-end GPUs.

### Compute pipeline

A compute pipeline is meant for performing abstract computation
on the GPU, apart from the complicated machinery of the graphics
pipeline. They are created with
[`vkCreateComputePipelines()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateComputePipelines.html).
This can provide better performance than using a graphics
pipeline if the desired operations don't need to produce a visual
image directly. Despite their abstract nature, they are still
used in the context of graphics work for "purely mathematical"
data transformations, such as effects applied to an
already-rendered image. They can also be used for other
applications, such as scientific simulations.

GPUs excel at linear algebra, owing to their highly parallel
nature and large number of cores. If you need to perform a
relatively simple operation over a large matrix, doing it on the
GPU with a compute shader may be faster than doing it on the CPU,
even if the CPU code is properly multithreaded.  Furthermore, the
shader code needed to perform the desired operation may be much
simpler to write than the equivalent CPU code; GPUs are intended
for this particular use case, and their APIs reflect this.

One compute pipeline wraps a single compute shader, which
contains the actual code intended to run on the GPU. Compute
shaders have a different execution context from graphics shaders:
they are given workloads from groups of work items called
_workgroups_, each of which represents a single shader invocation
and which may be run in parallel. A compute shader runs in the
context of a _global workgroup_, which can be divided into a
configurable number of _local workgroups_.  Shader invocations
within a local workgroup can communicate, sharing data and
synchronizing execution via barriers and the like.

### Ray tracing pipeline

Ray tracing pipelines are designed for simulating the behavior of
light at a high level of detail by tracing the paths of "beams"
of light as they travel through a scene's geometry.  They are
created via
[`VkcreateRayTracingPipelinesKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateRayTracingPipelinesKHR.html).
As you might guess from the suffix, they were introduced as a
recent extension to Vulkan, having been added to the spec in
December 2020.

Ray tracing pipelines are not the only way to access ray tracing
functionality in Vulkan; _ray queries_ can also be used to
perform ray tracing operations from within any shader stage.
Support for ray tracing pipelines is somewhat more widespread
than for ray queries as of April 2021, with 12% of GPUs
supporting pipelines vs. 2% for queries on Windows, according to
[vulkan.gpuinfo.org](https://vulkan.gpuinfo.org/listfeaturesextensions.php?platform=windows).
Those statistics indicate that neither of them is supported all
that widely, though, so support for either feature should
definitely not be taken for granted.

In any case, with either approach, ray tracing starts with
_acceleration structures_, which are opaque descriptions of the
geometry in a scene. There are two types, top-level and
bottom-level; a bottom- level acceleration structure contains
triangles or axis-aligned bounding boxes, while a top-level
acceleration structure contains references to a set of
bottom-level structures along with shading and transform
information for each.

Once acceleration structures have been created and are present on
the GPU, ray traversal can be started. This process is somewhat
similar to rasterization, but with the properties of the viewport
determined by the ray. After intersections between rays and
surfaces have been computed, a series of configurable culling
operations are performed before final results are calculated.

With a ray tracing pipeline, shaders can be specified for various
stages and possibilities in the ray tracing process: ray
generation, intersection, any-hit, closest hit, and miss. Ray
generation is to generate the initial rays, for instance via the
GLSL function `traceRayEXT()`. Intersection shaders calculate
intersections between rays and faces, any-hit shaders are run for
every potential intersction, and closest hit shaders are run for
the closest hit point to the start of the ray. A built-in
intersection shader can be used if the geometry is made of
triangles, and any-hit shaders can be omitted. Miss shaders are
run for rays that don't intersect the geometry.
