# Vulkan notes

The text of this file is made available under the [CC BY-SA
4.0](https://creativecommons.org/licenses/by-sa/4.0/legalcode)
license.

## Introduction

Vulkan is often described as a low-level API, but to me that's a
bit deceptive. After all, it's not like it has you writing
machine instructions for graphics devices. That level of detail
is still concealed from you, and it's mostly unclear what objects
in the API actually map onto the physical components or circuitry
of a given graphics device or in what manner (well, unless the
vendor speaks up about it). What Vulkan is is a
fairly _explicit_ API: its functions are precisely-defined and
narrow in scope, by and large. However, much of its design comes
from a relatively subjective place of trying to give graphics
developers control over what they have voiced a desire to have
control over. The explicitness is perhaps not so much in the
name of closely representing the design of graphics hardware as
it is in making the behavior of Vulkan operations predictable to
developers, especially in performance terms, and in letting them
dictate exactly what they need from the device and no more.
Therefore, getting a good holistic sense of what Vulkan is all
about is easier if you think about what graphics developers might
need fine control over to maximize performance.

Much of the complexity of Vulkan comes from two sources: graphics
devices are highly concurrent, and they have their own memory. To
get the best performance from a graphics device, you want to run
operations on it in parallel as much as possible, and you want to
have it using its own memory as much as possible. Much of Vulkan
is designed with at least one if not both of these goals in mind.
It gives you a variety of different ways to order work on the
device and synchronize operation between the device and the
host, and otherwise says little about what order device
operations will take place in. It also gives you a variety of
ways to transfer data between the device and host, gives you
tools to minimize overhead in host-device communication, and
allows you to precisely manage how resources are laid out in
device memory.

If you're trying to understand why a certain object is in the
Vulkan API, or how to make the best use of it, a good place to
start is to ask yourself "How does this help me express my
ordering requirements only as much as I truly need to?" and "How
does this help me make the best use of device memory and
minimize host-device interaction?".

## Setting up Vulkan

Here is, in order, roughly what needs to happen during the
initial setup:

1. A platform window needs to be initialized (just barely). This
   involves setting things like its width and height, title, any
   hints, etc.

1. A
   [`VkInstance`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkInstance.html) needs to be created (just barely). In order
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
      needs to work that we need to check for (SDL in particular
      provides the function
      [`SDL_Vulkan_GetInstanceExtensions()`](https://wiki.libsdl.org/SDL_Vulkan_GetInstanceExtensions)
      for this purpose).

   1. The desired
      [layers](https://vulkan.lunarg.com/doc/sdk/1.2.170.0/linux/layer_configuration.html),
      if any, must be specified and configured. Layers are Vulkan
      components that insert themselves into the call chains of
      Vulkan commands to provide features such as logging,
      tracing, or validations.

   1. If debug messages are desired, a debug messenger needs to
      be set up (this is necessary to get messages from the
      validation layers). This requires populating a
      [`VkDebugUtilsMessengerCreateInfoEXT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDebugUtilsMessengerCreateInfoEXT.html)
      struct, which takes a callback function to handle the debug
      messages among other things.

1. The available [physical
   devices](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-physical-device-enumeration)
   need to be enumerated via
   `vkEnumeratePhysicalDevices()` and at least one
   device needs to be chosen out of those available if a suitable
   one can be found. Many applications have minimum requirements
   for the graphics hardware they utilize; physical devices can
   be filtered and ranked based on these.

1. At least one [logical
   device](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-devices)
   needs to be generated from any physical devices that need to
   be interacted with. A logical device is an abstract
   representation of a physical device that we can actually send
   drawing commands to, allocate memory with, etc. In order to
   create a logical device, we need to specify what
   [queues](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#devsandqueues-queues)
   we are going to create along with it (see "Queues" below).

At this point, we are still a ways away from being able to
actually draw to the window. What we do have are the objects that
are likely to survive for the duration of the application's run
(unless the user wants to switch graphics cards). Everything we
create after this point may need to be torn down and recreated
periodically, and in some cases may be torn down and recreated
quite often. So, it would be reasonable to look on these steps as
constituting the initialization of a Vulkan graphics envrionment,
with the remaining steps constituting its "runtime".

## "Runtime"

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
   processing. Swapchains facilitate synchronization with the
   refresh rate of the display, and can be used to implement
   techniques like double and triple buffering.

   A swapchain will need to be set up at least once, but can be
   long-lived under some circumstances. However, because it is
   associated with a surface, it needs to be reconstructed if the
   surface changes, such as during a window resize.

1. To actually make use of the `VkImage`s in the swapchain, we
   need to create
   [`VkImageView`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#resources-image-views)s
   to them. These are essentially objects that describe how the
   images should be treated during rendering, such as the image's
   dimensions, the subset of the image that should be rendered,
   the subresource range to make available, etc.

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
   which represent a set of operations for the GPU to perform.

1. The last major piece of machinery we need is a way to tell the
   graphics hardware to actually make use of everything we've set
   up. This is via
   [`VkCommandBuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandBuffer.html)s;
   see below.

## Loading function pointers

If you're dynamically loading the Vulkan library, you'll need to
retrieve pointers to its functions at runtime. This is not a bad
idea, [for both compatability and performance
reasons](https://gpuopen.com/learn/reducing-vulkan-api-call-overhead/).
Even if you link to Vulkan, though, functions enabled by
extensions may not be immediately available; you may need to get
pointers to them after you've enabled the relevant extension.

There are two different functions used for this purpose,
[`vkGetInstanceProcAddr()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetInstanceProcAddr.html)
and
[`vkGetDeviceProcAddr()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetDeviceProcAddr.html).
`vkGetInstanceProcAddr()` is used to load functions that take a
`VkInstance` as their first argument, whereas
`vkGetDeviceProcAddr()` is used to load functions that take a
`VkDevice` as their first argument.  You can actually use
`vkGetInstanceProcAddr()` for everything, but using
`vkGetDeviceProcAddr()` for the relevant functions avoids some
overhead.

You might worry that there's a chicken-and-egg problem with
`vkGetInstanceProcAddr()`. After all, if it requires a
`VkInstance`, how will you get a pointer to `vkCreateInstance()`
so you can make one first? Luckily, `vkGetInstanceProcAddr()`
will still return pointers to a few functions even if `instance`
is null, and `vkCreateInstance()` is one of them.
`vkEnumerateInstanceLayerProperties()` and
`vkEnumerateInstanceExtensionProperties()` are too, which is
handy, as we'll see shortly (check the spec for the full list).

Pointers returned by the `*ProcAddr()` functions are of type
`PFN_vkVoidFunction`, and must be cast to the right function
pointer type before use. In C++, this regrettably requires
`reinterpret_cast` (one argument in favor of using
[`Vulkan-Hpp`](https://github.com/KhronosGroup/Vulkan-Hpp)). To
save you the trouble of typing out the right function pointer
type, the Vulkan headers define `PFN_*` types for all the
functions in the API (i.e. `vkCreateInstance()`'s would be
`PFN_vkCreateInstance`). Very nice of them!

Depending on how you dynamically load Vulkan, you may not have
`vkGetInstanceProcAddr()` right away. If you're using SDL, after
either calling
[`SDL_Vulkan_LoadLibrary()`](https://wiki.libsdl.org/SDL_Vulkan_LoadLibrary)
or creating a window with the `SDL_WINDOW_VULKAN` flag, you can
use
[`SDL_Vulkan_GetVkGetInstanceProcAddr()`](https://wiki.libsdl.org/SDL_Vulkan_GetVkInstanceProcAddr)
to get a pointer to it. If you're using GLFW,
[`glfwGetInstanceProcAddress()`](https://www.glfw.org/docs/3.3/group__vulkan.html#gadf228fac94c5fd8f12423ec9af9ff1e9)
provides an interface to `vkGetInstanceProcAddr()`. You can also
use a library made specifically for this purpose such as
[volk](https://github.com/zeux/volk).

## Layers

Layers are optional parts of the Vulkan call chain which can be
enabled when creating an instance. You put the layers you want to
enable into the `ppEnabledLayerNames` field of the
[`vkInstanceCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkInstanceCreateInfo.html),
although of course it's a good idea to
check for their presence in the host environment first with
[`vkEnumerateInstanceLayerProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkEnumerateInstanceLayerProperties.html).

Anyone can write a new Vulkan layer and make it available on a
specific host. See ["Architecture of the Vulkan Loader
Interfaces"](https://vulkan.lunarg.com/doc/sdk/1.2.176.1/linux/loader_and_layer_interface.html)
in the Vulkan SDK docs for the specifics.

## Extensions

Extensions are Vulkan add-ons that define new commands and types.
Some of them are _registered_, meaning they have been
incorporated into Khronos' [specification
repository](https://www.khronos.org/registry/vulkan/#repo-docs);
these are defined in Vulkan's core headers, although support for
them depends on the graphics driver. Extensions can also be
provided by layers, though, so you can write your own extensions
if you want.

There are two kinds of extensions, instance and device
extensions. Instance extensions are enabled when creating an
instance by adding their names to the `ppEnabledExtensionNames`
field of
[`vkInstanceCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkInstanceCreateInfo.html);
device extensions are enabled
when creating a logical device by adding their names to the
`ppEnabledExtensionNames` field of
[`VkDeviceCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceCreateInfo.html).

In both cases, it's advisable to check for the presence of the
extensions you want to enable first. Instance extensions are
checked for via
[`vkEnumerateInstanceExtensionProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkEnumerateInstanceExtensionProperties.html),
while device extensions are checked for via
[`vkEnumerateDeviceExtensionProperties`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkEnumerateInstanceExtensionProperties.html)
(the latter takes a physical device to query). In both cases, you
can provide the name of a layer, in case the extensions you're
looking for are made available that way.

## Validations

The most commonly-used layer is probably the [validation
layer](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/khronos_validation_layer.md),
which is included in the Vulkan SDK and performs automatic error
checking. Vulkan does very little error checking on its own since
it's designed to be lean and performant. That can make for
frustrating debugging, though, and it also means you don't get
much feedback if you're doing something technically permissible
but less-than-ideal. The validation layer can take care of both
of these, so it's a good idea to have it turned on in
development.

At the time of writing, the name of the validation layer is
`VK_LAYER_KHRONOS_validation`. All you have to do to enable it is
add this name to `ppEnabledLayerNames` when creating your
instance (provided it's available). However, you may wish to
configure its behavior. By default, it performs

* [shader
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/core_checks.md#shader-validation-functionality)
  (mostly simple checks for shader interface consistency),
* shader validation caching (although you probably need to create
  a
  [`VkValidationCacheEXT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkValidationCacheEXT.html)
  to take advantage of this…I'm not sure if this is required or
  not though),
* [thread safety
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/thread_safety.md)
  (checks for properly-synchronized access to Vulkan objects from
  multiple threads),
* [stateless parameter
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/stateless_validation.md)
  (proper use of Vulkan structs and enums, null pointer checks,
  etc.),
* [object lifetime
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/object_lifetimes.md)
  (checks for valid references, correct freeing/destroying, etc.),
* [various "core"
  validations](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/core_checks.md)
  (checks for proper pipeline setup, valid command buffers,
  memory availability, etc.),
  and
* [protection against duplicate non-dispatchable object
  handles](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/handle_wrapping.md)
  (ensures that duplicate object handles are managed correctly by
  the validation layers; some systems do not return unique
  identifiers for handles),

and does not perform

* [GPU-assisted
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/gpu_validation.md) (provides additional diagnostic info
  from shaders),
* [reservation of a descriptor set binding slot for use in
  performing GPU-assisted
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/gpu_validation.md#gpu-assisted-validation-options)
  (modifies `VkPhysicalDeviceLimits::maxBoundDescriptorSets` to
  return a number 1 less than it otherwise would, in order to
  ensure there is a free descriptor set binding slot available
  for GPU-assisted validation to use; it needs to have one),
* [debug printing from
  shaders](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/debug_printf.md)
  (provides a `printf()`-like function in GLSL in concert with
  [`GL_EXT_debug_printf`](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GLSL_EXT_debug_printf.txt)),
* [best-practices
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/best_practices.md)
  (checks for stuff that is permitted but not advisable), and
* [synchronization
  validation](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/synchronization.md)
  (checks for missing or incorrect synchronization between
  commands that perform memory accesses).

The disabled-by-default features are computationally-intensive;
you can enable them all-at-once if you like but your application
may become sluggish. Khronos
[advises](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/khronos_validation_layer.md#vk_layer_khronos_validation)
that you enable them piecemeal for this reason.

You can configure which of these features are and aren't enabled
in a variety of ways: a graphical program, a config file, a set
of environment variables, or a programmatic interface. See
["Layers Overview and
Configuration"](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/LAYER_CONFIGURATION.md)
for everything but the programmatic interface. The programmatic
approach is to add a
[`VkValidationFeaturesEXT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkValidationFeaturesEXT.html)
to the `pNext` chain of your `VkCreateInstanceInfo` when creating
your instance. This requires the extension
[`VK_EXT_validation_features`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_EXT_validation_features.html)
to be enabled.

By default, messages from the validation layer are written to the
standard output stream. This might be fine for your use case, but
you might prefer to have them talk to your own logging interface,
produce a stack trace, drop into a debugger, etc. In that case,
you can enable the
[`VK_EXT_debug_utils`](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/master/docs/khronos_validation_layer.md#debugutils)
extension, which allows you to register callbacks that can
receive messages from the validation layer. You can also control
what sorts of messages you would like to receive.

Both of these extensions have convenient macros for their names
defined in the Vulkan core headers. The debug utils extension
name is given by `VK_EXT_DEBUG_UTILS_EXTENSION_NAME`, and the
validation features extension name is given by
`VK_EXT_VALIDATION_FEATURES_EXTENSION_NAME`.

## Instances

There's no global state in Vulkan, so a
[`VkInstance`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkInstance.html)
is the first waystation on the path to building up a nicely
purring Vulkan environment. It's created via
[`vkCreateInstance()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateInstance.html).

Everything in
[`VkInstanceCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkInstanceCreateInfo.html)
is optional (well, aside from the `sType`). Unless you are
compiling a release build, though, you probably want to enable
the validation layer here, along with any of its accompanying
extensions you might want to make use of. You also may want to
fill out a
[`VkApplicationInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkApplicationInfo.html)
in order to specify things like the name and version number of
your application and the version of the Vulkan API you're
depending on; if your application becomes popular, graphics
driver vendors may build special cases for it into their drivers.
(There is a convenient macro
[`VK_MAKE_API_VERSION()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_MAKE_API_VERSION.html)
you can use to get the Vulkan API version number in the right
format. If you're using Vulkan 1.2.x, the right thing to put for
`apiVersion` is `VK_MAKE_API_VERSION(0, 1, 2, 0)`.)

To destroy an instance, use
[`vkDestroyInstance()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyInstance.html).
Everything created with the instance must have been destroyed
first.

## Physical devices

In the context of Vulkan, a physical device is a single complete
Vulkan implementation visible to the host. This generally
corresponds to a piece of hardware, such as a graphics card or a
CPU with integrated graphics, presented by a Vulkan-capable
driver. There is little than can be done in Vulkan without going
through one somehow. They are represented through
[`VkPhysicalDevice`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDevice.html)
handles, and don't need to be created or destroyed.

In order to select a physical device, the available devices need
to be enumerated via
[`vkEnumeratePhysicalDevices()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkEnumeratePhysicalDevices.html).
This involves a little song-and-dance in which you first pass
a null pointer for the array of devices, which causes the device
count to be set to the right number, which then allows you to
call the function again with an array of the right length.

Once you've done this, you can use
[`vkGetPhysicalDeviceProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceProperties.html)
on each device in the array; this populates a
[`VkPhysicalDeviceProperties`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceProperties.html)
with the device's name, vendor, capabilities, etc. You can also
use
[`vkGetPhysicalDeviceProperties2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceProperties2.html),
which takes a pointer to a
[`VkPhysicalDeviceProperties2`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceProperties2.html);
you can use the `pNext` field of that struct to get extra
information about the device beyond what
`VkPhysicalDeviceProperties` expresses (see the spec for
details).

You can get a _lot_ of information about a device this way, and
it can be a bit challenging to figure out what you should look
out for. Unfortunately, it's hard to give any hard-and-fast rules
about, because every application has different requirements.
Early on in development, you may not have a good idea of what
those are, so you don't need to stress about it too much. You
could pick based on
[`VkPhysicalDeviceType`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceType.html)
if you would prefer a discrete graphics device over integrated
graphics. You could also use
[`vkPhysicalDeviceMemoryProperties2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceMemoryProperties2.html)
to get a sense of how much video memory the device has, or how
heavily it's already being used, and pick based on that. You
could also develop a more complicated heuristic that took both of
these and other things into account, or you could just pick at
random. In any case, sooner or later it's a good idea to give the
user an interface to switch devices manually if they want, since
they may know things your algorithm doesn't consider.

As your application develops, it will become clearer what its
hard and soft requirements are in graphical terms. If you want to
have different levels of graphics quality, the data here will
help you pick a default setting for a given device. Some devices
may also not make the cut at all even as far as the bare minimum
goes, and you can rule them out here—that's much better than
having the application crash later because the device in use
couldn't do something it needed. If the user doesn't have any
available devices that satisfy your most basic requirements, you
can let them know here gracefuly, ideally informing them
specifically where their devices don't measure up.

Also, a couple things you might want to note—it's worth keeping
track of the information in `VkPhysicalDeviceMemoryProperties`,
because you'll need it later (you'll find out why in "Memory
management"). You might also want to take a gander at "Images"
under "Resources", and then use
[`vkGetPhysicalDeviceFormatProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceFormatProperties.html)
to store feature support info for the image formats you're
interested in.

### Queue families

Most of the things you might want to do with Vulkan are done by
submitting _commands_ to a _queue_. We cover both of those
concepts elsewhere. What's important right now is that a physical
device has _queue families_ from which queues can be selected,
and you need to investigate them if you ultimately want to have
some queues to work with. This is done with
[`vkGetPhysicalDeviceQueueFamilyProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceQueueFamilyProperties.html)
or
[`vkGetPhysicalDeviceQueueFamilyProperties2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceQueueFamilyProperties2KHR.html);
the latter allows you to get some extra info (see the spec for
details).

A particularly important member of the
[`VkQueueFamilyProperties`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkQueueFamilyProperties.html)
struct you fill for each queue family is `queueFlags`, a bitmask
of
[`VkQueueFlagBits`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkQueueFlagBits.html).
This tells you if the queues in the family support graphics
operations (kinda self-explanatory), compute operations (doing
"general" computation on the GPU), and/or transfer operations
(moving stuff around in memory). Each of these correspond to
different sets of commands. If you want your application to
display graphics in a platform window, you also need
[`vkGetPhysicalDeviceSurfaceSupportKHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceSurfaceSupportKHR.html),
which will tell you if queues in the given family support
presentation to the given surface
([`vkQueuePresentKHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueuePresentKHR.html)).
A mature game will generally need to do all of these things.

In any case, this is the time to pick which queue families you're
going to use for which sorts of operations. It's generally a good
idea to pick the queue family that's most specialized for the
type of operations in question (i.e. has the least other
capabilities), because that queue is most likely to be optimized
for those operations. When you actually create the queues you
want, you'll refer to the queue families by index. Note that a
queue family which supports graphics or compute operations always
has support for transfer operations as well, even if it doesn't
say so; it may still be worth making a special transfer queue if
there's a queue family that's specialized for this purpose, but
otherwise you can have a queue do double-duty.

## Logical devices

Once you've picked out a physical device and combed through its
queue families, you need to make what's called a _logical device_
from it in order to actually make use of it. The process of
creating the logical device also creates the queues you need, so
once you've done this you can starting submitting commands to
them and making things happen.

The separation of concerns between a logical and a physical
device might seem a bit strange. Why wouldn't Vulkan just have
you make your queues and do the other work you need to do with
the physical device directly?  Well, there's not a 1:1
relationship between a physical device and a logical device—a
single logical device can be made from multiple physical devices
if they're sufficiently similar (like a bunch of identical cards
in a render farm) and multiple logical devices can be made from
the same physical device (like if a Vulkan application depends on
a library or loads a plugin that also uses Vulkan internally). If
you're writing a game engine, you're probably not too worried
about the former use case, but Vulkan is designed to serve a lot
of different crowds. It also just provides a rather handy
interface—you can specify your device extensions and desired
queues in one go and get a nice object to carry around the
resulting context in.

To create a logical device from a physical device, you want
[`vkCreateDevice()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDevice.html).
You've pretty much already done the necessary work to call this
properly—just specify the queue families and how many queues you
want along with the device extensions and features you need. Note
that there's usually not much of a reason to make more than one
queue from the same family if you're writing a regular desktop
application; the most efficient way to submit work to a queue is
to group it all into a single large batch beforehand as much as
possible, since queue submission is an expensive process and
queues run commands as asynchronously as they can.

To destroy a logical device, use
[`vkDestroyDevice()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyDevice.html)—pretty
straightforward. The one thing to keep in mind is that all the
objects that were made with the device need to be destroyed
beforehand. You can use
[`vkDeviceWaitIdle()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDeviceWaitIdle.html)
to make sure that you're not destroying a device with anything
still pending on it, but this will block indefinitely if you
haven't destroyed those other objects first.

It's possible for a logical device to become _lost_ for various
reasons, such as execution timeout, memory exhaustion, driver
bugs, etc. If this occurs, relevant commands will return
`VK_ERROR_DEVICE_LOST`, and a new logical device will need to be
made before the application can continue. In some cases, the
physical device will _also_ be lost, in which case trying to
create a new logical device will return `VK_ERROR_DEVICE_LOST` as
well. This generally indicates a serious underlying problem such
as disconnected or malfunctioning graphics hardware. If these
problems have not brought down the operating system and your
application is still alive, you may be able to recover if you can
make use of an alternate physical device.

Also, just another tip, along the lines of those in "Physical
devices"—once you've got a logical device, you can create images,
which means you can use
[`vkGetImageMemoryRequirements()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetImageMemoryRequirements.html)
to figure out which memory types support which image formats on
the physical device (see "Images" under "Resources" for more on
images). If you saved the memory type and image format support
information when choosing a physical device, you can cycle
through the supported formats here, create an image for each
format, and query its memory requirements. This will be handy
information to have cached, as you'll see in "Memory management".

## Queues

In order to actually do work on a device with Vulkan, commands
need to be submitted to it. These commands are submitted through
Vulkan objects called queues.

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
created with when `vkDestroyDevice()` is called on the device in
question.

## Command buffers

_Command buffers_, represented by
[`VkCommandBuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandBuffer.html),
are used to submit _commands_ to a device queue. They are
allocated using
[`vkAllocateCommandBuffers()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateCommandBuffers.html),
which requires specifying a device, a _command pool_, and the
_level_ of the buffers to be allocated. Rather than execute
commands immediately, commands are _recorded_ onto command
buffers to be later submitted to a device queue, which allows
command buffers to be set up concurrently with rendering
operations.

Command buffers can be used to execute a wide variety of
commands. They are all specified with functions that follow the
naming format `VkCmd*`. Some of the most notable are described
below in their own subsections.

A _command pool_, represented by
[`VkCommandPool`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCommandPool.html),
is an opaque object used to allocate memory for command
buffers on a device. They can be _reset_ using
[`vkResetCommandPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkResetCommandPool.html),
which reinitializes all the command buffers allocated from the
pool and returns the resources they were using back to the
pool. A command pool can also be _trimmed_ using
[`vkTrimCommandPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkTrimCommandPoolKHR.html),
which frees up any unused memory from the pool without
affecting the command buffers allocated from it; this is
useful to e.g. reclaim memory from a specific command buffer
that has been reset without needing to reset the whole pool.

Every command buffer has a _level_, which is either _primary_ or
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

### Binding to a command buffer

Many of the objects used in a command buffer need to be bound to
it beforehand. Once bound, subsequent operations that make use of
the type of object that was bound will generally use the bound
object. This is main way that commands that act on an object not
supplied as a parameter know what to work with.

To bind a pipeline, use
[`vkCmdBindPipeline()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindPipeline.html).
This command binds the given pipeline to a specific bind point
based on its type (graphics, compute, or ray tracing). It is
possible to bind pipelines of different type to the same command
buffer; the spec says that "binding [to] one [point] does not
disturb the others." A bound graphics pipeline controls all
commands with "Draw" in the name, a bound compute pipeline controls all
commands with "Dispatch" in the name, and a bound ray tracing
pipeline controls all commands with "TraceRays" in the name.

To bind vertex and index buffers, use
[`vkCmdBindVertexBuffers()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindVertexBuffers.html)
(or
[`vkCmdBindVertexBuffers2EXT()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindVertexBuffers2EXT.html))
and
[`vkCmdBindIndexBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindIndexBuffer.html).
As you can probably tell from the function names,
`vkCmdBindVertexBuffers()` takes a list of vertex buffers,
whereas `vkCmdBindIndexBuffer()` takes only a single index
buffer. This is because vertex _attributes_ are put together from
the vertex buffers, and the index buffer specifies indices for
complete sets of those attributes, which are each made available
in the vertex shader. The manner in which this occurs is defined
during pipeline creation. (`vkCmdBindVertexBuffers2EXT()` allows
size and stride information for the vertex buffers to be
specified at binding time instead of during pipeline creation.)

To bind descriptor sets, use
[`vkCmdBindDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindDescriptorSets.html).
This takes an array of descriptor sets, a pipeline layout, and
the type of pipeline (i.e. the pipeline bind point) that will use
the descriptor sets. If the descriptor sets being bound include
dynamic uniform or storage buffers, offsets into these buffers
can be specified here as well.

There are a few other binding commands enabled by extensions; see
[`vkCmdBindTransformFeedbackBuffersEXT()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindTransformFeedbackBuffersEXT.html),
[`vkCmdBindPipelineShaderGroupNV()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindPipelineShaderGroupNV.html),
and
[`vkCmdBindShadingRateImageNV()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindShadingRateImageNV.html).

### Drawing

Draw commands take a set of vertices and submit it to a graphics
pipeline (see "Pipelines"). This can be used to e.g. render a 3D
model, among many other things. All the draw commands are named
in the format `VkCmdDraw*`. For relatively obvious reasons, they
should be called inside of a render pass instance.

Both the format of vertices in memory and how they are processed
by the graphics pipeline are very flexible. See
[`VkVertexInputBindingDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputBindingDescription.html)
and
[`VkVertexInputAttributeDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputAttributeDescription.html)
for more information on laying out vertices, and
[`VkPrimitiveTopology`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPrimitiveTopology.html)
for the strategies that can be used by the graphics pipeline for
assembling vertices into primitives. [Ch. 21: Drawing
Commands](https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/chap21.html)
and [Ch. 22: Fixed-Function Vertex
Processing](https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/chap22.html)
in the spec cover this topic in detail.

The most commonly-used draw commands can be categorized based on
whether or not they take a vertex index buffer. Without an index
buffer, vertices are assembled one-by-one into primitives based
on their index in the vertex buffer. With an index buffer, the
order in which to assemble the vertices into primitives can be
specified explicitly. The advantage of using an index buffer is
that vertices can be reused, which avoids the need to duplicate
vertices used to assemble more than one primitive. 3D model
formats often work this way. In either case, the primitive
toplogy in use dictates how the vertices are assembled once an
ordering is established.

The two most straightforward draw commands are
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html)
and
[`vkCmdDrawIndexed()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexed.html).
These simply take a filled vertex buffer and possible index
buffer and submit them to the graphics pipeline.

Another way of categorizing draw commands is by whether or not
they perform an indirect draw. Indirect draws read vertex data
from a buffer during execution as opposed to loading it
beforehand. This is useful if the vertex data is e.g. generated
by a compute shader as opposed to being handled on the CPU side,
which can be used for high-performance rendering techniques. See
[this GPU-driven rendering
article](https://vkguide.dev/docs/gpudriven/gpu_driven_engines/)
and [these
slides](https://www.advances.realtimerendering.com/s2015/aaltonenhaar_siggraph2015_combined_final_footer_220dpi.pdf)
for some more information on that sort of thing.

The "simple" draw commands have their indirect equivalents in
[`vkCmdDrawIndirect()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndirect.html)
and
[`vkCmdDrawIndexedIndirect()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexedIndirect.html).
There is also
[`vkCmdDrawIndexedIndirectCount()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexedIndirectCount.html),
which gets its draw count parameter from a buffer instead of
having it passed directly, and
[`vkCmdDrawIndirectByteCountEXT()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndirectByteCountEXT.html),
which gets its vertex count from a buffer. The latter comes from
the
[`VK_EXT_transform_feedback`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_EXT_transform_feedback.html)
extension and is not recommended for use outside of translation
layers for other 3D graphics APIs.

There are also three draw commands introduced by the
[`VK_NV_mesh_shader`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_NV_mesh_shader.html)
mesh shading extension. However, my GPU does not support mesh
shading, so I'm not going to cover these.

### Copying images and buffers

There are four commands for simple image/buffer to buffer/image
copying, a command for image copying with scaling and format
conversion, and a command for resolving a multisample image. They
have `*2KHR()` variants via the
[`VK_KHR_copy_commands2`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_copy_commands2.html)
extension.

These commands have a number of valid usage requirements; the
spec has [the
details](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#_common_operation).

#### Simple copying

These commands copy a list of regions of a buffer or image, specified with
[`VkBufferCopy`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBufferCopy.html)s
or
[`VkImageCopy`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCopy.html)s.
They don't do format conversion; image-to-image copying must be
between
[compatible](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#formats-compatibility)
formats, and buffer-to-image copying is done with the assumption
that the data in the buffer region(s) matches the image format.

The `*2KHR()` commands here are are mostly the same in functional
terms as the original commands but are more extensible. Those
that take
[`VkBufferImageCopy2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBufferImageCopy2KHR.html)
can perform a rotated copy using
[`VkCopyCommandTransformInfoQCOM`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCopyCommandTransformInfoQCOM.html).

The commands are as follows:

  * for image-to-image copy, [`vkCmdCopyImage()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyImage.html)
    or
    [`vkCmdCopyImage2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyImage2KHR.html);
  * for buffer-to-buffer copy, [`vkCmdCopyBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyBuffer.html)
    or
    [`vkCmdCopyBuffer2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyBuffer2KHR.html);
  * for image-to-buffer copy, [`vkCmdCopyImageToBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyImageToBuffer.html)
    or
    [`vkCmdCopyImageToBuffer2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyImageToBuffer2KHR.html);
  * for buffer-to-image copy, [`vkCmdCopyBufferToImage()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyBufferToImage.html)
    or
    [`vkCmdCopyBufferToImage2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyBufferToImage2KHR.html).

#### "Sprite-style" copying

If you need to do format conversion and/or scaling as part of
your copy operation, you can use
[`vkCmdBlitImage()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBlitImage.html)
or
[`vkCmdBlitImage2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBlitImage2KHR.html).
With these commands, the formats of the source and destination
images have looser requirements than with the "simple" image
copying commands, and the source and destination regions can
differ in size. If the regions do differ in size, scaling is
performed, and the filtering algorithm to use while scaling can
be chosen (see
[`VkFilter`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFilter.html)
for the available algorithms).

`vkCmdBlitImage2KHR()` can also perform a rotation as part of the
copy.

These commands are not intended for use with multisampled images,
unlike the following commands.

#### Multisample resolve

If you need to resolve a multisample color image to a
non-multisample color image, you can use
[`vkCmdResolveImage()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdResolveImage.html)
or
[`vkCmdResolveImage2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdResolveImage2KHR.html).
These are similar to the "simple" image-image copying commands,
but resolve all the samples corresponding to a single pixel
location in the source image into a single sample in the
destination image.


starting and managing render passes and subpasses, binding
resources like pipelines and buffers to the command buffer,
and making draw calls on the associated device.

## Resources

There are two main types Vulkan uses to keep track of data. One
of them is `VkBuffer`, which is relatively similar to a plain
array, and the other is `VkImage`, which is basically a fancy
container for
[texels](https://en.wikipedia.org/wiki/Texel_\(graphics\)).

Of note, these two types are the main tools you have for
interacting with device memory in the API. When you call
[`VkAllocateMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateMemory.html),
all you end up with is an opaque handle
[`VkDeviceMemory`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceMemory.html),
which you have to bind to a `VkBuffer` or `VkImage` to make use
of. Concomitant with this, they are the main way of getting data
through the API into your shader code.

### Buffers

The buffer, represented by `VkBuffer`, is a data type that's kind of
like a C array with some extra context. They're created via
[`vkCreateBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateBuffer.html),
which takes a
[`VkBufferCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBufferCreateInfo.html).
It's rather enlightening to take a brief look at a couple of that
struct's fields:

* `VkDeviceSize size`: this is the size of the `VkBuffer` in the
  C array sense; it's currently a [typedef of
  `uint64_t`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceSize.html);
* `VkBufferUsageFlags usage`: these set what the buffer can be
  used for; among other things, they include:
  * `VK_BUFFER_USAGE_TRANSFER_SRC_BIT` and
    `VK_BUFFER_USAGE_TRANSFER_DST_BIT`, which say the buffer
    can be the source or destination of a transfer command (see
    "Copying images and buffers"),
  * `VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT`,
    `VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT`,
    `VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT`, and
    `VK_BUFFER_USAGE_STORAGE_BUFFER_BIT`, all of which
    basically say the buffer can occupy a descriptor set slot, in
    various ways (see "Resource descriptors"),
  * `VK_BUFFER_USAGE_INDEX_BUFFER_BIT`, and
    `VK_BUFFER_USAGE_VERTEX_BUFFER_BIT`, both of which have to
    do with getting vertices into a graphics pipeline, and
  * `VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT`, which basically says
    the buffer can be used to pass parameters at runtime to
    various commands.

There's a bit more to buffers than this, but that gives you a
sense of their personality in the context of Vulkan. They provide
a means to ferry "arbitrary" data around that needs to play some
role on the device but doesn't need the `VkImage` treatment.

### Images

The image, represented by `VkImage`, is a data type designed to
hold information you might find in a texture, like color or depth
values. It has a fixed format, dimensionality (1–3 dimensions),
tiling, layers, and MIP levels, on top of the sorts of usage and
general flags etc. parameters that buffers have.

Images are created via
[`vkCreateImage()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateImage.html),
which takes a
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html).
Like buffers, it's enlightening to examine the fields of
`VkImageCreateInfo` if you want to get a sense of what images are
all about, but there are a lot more fields to mull over there
than buffers have.

#### Creation

##### Format

The `VkImageCreateInfo` field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormat.html">VkFormat</a>
format</code> describes the binary format of the image data. Not
all formats are compatible with all types of memory, as we'll see
in more detail in the "Memory management" section.

As you'll see if you check out the `VkFormat` spec section,
there's a huge number of possible formats that can seem rather
mystifying to stare at initially. Luckily, we have a few places
we can look to get our bearings.

One helpful place to look is [43.3 "Required Format
Support"](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/chap43.html#features-required-format-support)
in the Vulkan spec. This tells you which features are required to
be supported for which image formats, which gives you a sense of
what you might want to use a given format for. There's still a
lot of formats to look over there, though, so maybe we can narrow
the list down further.

Another interesting thing to consider is the behavior of
[`vulkaninfo`](https://vulkan.lunarg.com/doc/view/latest/linux/vulkaninfo.html)
when it's examining the available memory types. It displays which
image formats each type of memory supports, and it only examines
a small subset of the possible formats. Since `vulkaninfo` is an
official Khronos utility, they probably know a thing or two about
which formats are particularly commonplace. `vulkaninfo` is [free
software](https://www.gnu.org/philosophy/free-sw.html) (thanks
Khronos!!), so let's check out the format list it uses:

([`Vulkan-Tools/vulkaninfo/vulkaninfo.h:1548`](https://github.com/KhronosGroup/Vulkan-Tools/blob/a680671d95bf7b3846cb20f1cbfc1c405db0511b/vulkaninfo/vulkaninfo.h#L1548))

```cpp
const std::array<VkFormat, 8> formats = {
    color_format,
    VK_FORMAT_D16_UNORM,
    VK_FORMAT_X8_D24_UNORM_PACK32,
    VK_FORMAT_D32_SFLOAT,
    VK_FORMAT_S8_UINT,
    VK_FORMAT_D16_UNORM_S8_UINT,
    VK_FORMAT_D24_UNORM_S8_UINT,
    VK_FORMAT_D32_SFLOAT_S8_UINT,
};
```

([`Vulkan-Tools/vulkaninfo/vulkaninfo.h:1350`](https://github.com/KhronosGroup/Vulkan-Tools/blob/a680671d95bf7b3846cb20f1cbfc1c405db0511b/vulkaninfo/vulkaninfo.h#L1350))

```cpp
const VkFormat color_format = VK_FORMAT_R8G8B8A8_UNORM;
```

`VK_FORMAT_R8G8B8A8_UNORM` is your bog-standard 8-bit RGBA color
format. It's unsigned (that's the meaning of `U`) and
normalized (that's the meaning of `NORM`). It's also in a [linear
color
space](https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-24-importance-being-linear),
which is handy for rendering but not necessarily ideal for
display—humans don't perceive color in a linear fashion.

For this reason, there's also `VK_FORMAT_R8G8B8A8_SRGB`. sRGB is
a color space designed in the '90s for computer graphics
purposes. I'd love to link to the spec for it, but it's behind a
stupid paywall just like the IEEE 754 (floating point
arithmetic), C, and C++ standards. When will the world come to
its senses?! Anyway, you can at least read a [minorly-wrong
version](https://www.w3.org/Graphics/Color/sRGB.html) and shake
your fist at the W3C, the IEC, and society in general in the
meantime. The gist of sRGB is that it's designed to work nicely
with both the way CRT monitors display color and the way humans
tend to perceive color in a relatively dim, diffusely-lit room
like someone might watch a movie in. Even though it's old and
almost nobody uses CRTs anymore, it's still the most common color
space used for computer graphics as of 2021, and Vulkan
accordingly requires every implementation to support
`VK_FORMAT_R8G8B8A8_SRGB` as a format for swap chain images
(which are what actually get drawn to the platform window). When
`VK_FORMAT_R8G8B8A8_SRGB` is used as the swap chain image format,
color data written to a swap chain image from the fragment shader
is converted to sRGB beforehand, preparing it to be displayed on
a monitor. sRGB isn't perfect, and Vulkan can support other color
spaces if the device provides for it (see
[`VkColorSpaceKHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkColorSpaceKHR.html)
in the spec), but sRGB is the only one you can count on universal
support for as far as realtime graphics are concerned.

Anyway, this leaves

* `VK_FORMAT_D16_UNORM`,
* `VK_FORMAT_X8_D24_UNORM_PACK32`,
* `VK_FORMAT_D32_SFLOAT`,
* `VK_FORMAT_S8_UINT`,
* `VK_FORMAT_D16_UNORM_S8_UINT`,
* `VK_FORMAT_D24_UNORM_S8_UINT`, and
* `VK_FORMAT_D32_SFLOAT_S8_UINT`.

Looking at the "Required Format Support" charts, we can see that
all of these appear to be intended for depth/stencil use (storing
things like [depth
maps](https://en.wikipedia.org/wiki/Depth_map), [stencil
buffers](https://en.wikipedia.org/wiki/Stencil_buffer), etc).
Returning to the `VkFormat` spec, we can note that `D` is for
"depth component", so `VK_FORMAT_D16_UNORM` is a format with only
a 16-bit unsigned normalized depth component. `S` is for "stencil
component", so `VK_FORMAT_S8_UINT` is a format with only an 8-bit
unsigned integer stencil component. Some of the formats have
both, such as `VK_FORMAT_D16_UNORM_S8_UINT`, a 24-bit,
two-component format that combines the previous two formats.
`VK_FORMAT_X8_D24_UNORM_PACK32` is a two-component format with
its 8 MSBs "unformatted" and the remaining 24 bits representing
an unsigned normalized depth value (see [43.1.4 "Representation
and Texel Block
Size"](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#texel-block-size)
in the Vulkan spec). `SFLOAT` is for "signed floating-point", as
you might expect; `VK_FORMAT_D32_SFLOAT` is a one-component
format with a 32-bit signed floating point depth component.

Which of these you might use depends on the circumstances, of
course, but are any of them particularly significant? ["Required
Format
Support"](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/chap43.html#features-required-format-support)
indicates that `VK_FORMAT_D16_UNORM` must be supported for use as
a depth/stencil attachment, along with at least one of
`VK_FORMAT_X8_D24_UNORM_PACK32` and `VK_FORMAT_D32_SFLOAT`, and
at least one of `VK_FORMAT_D24_UNORM_S8_UINT` and
`VK_FORMAT_D32_SFLOAT_S8_UINT`. `VK_FORMAT_D16_UNORM` and
`VK_FORMAT_D32_SFLOAT` are also guaranteed to be samplable (see
"Samplers") and usable as a blitting source (see "'Sprite-style'
copying" under "Command buffers"). `VK_FORMAT_D16_UNORM` appears
to be the common denominator among these, but it doesn't have a
stencil component and lacks the precision of the alternatives.
It's possibly worth testing at device creation time to see which
of the other possible depth/stencil attachment formats you can
make use of, depending on your application's needs (you can do
this with
[`vkGetPhysicalDeviceFormatProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceFormatProperties.html)).

##### Usage

Images have a <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageUsageFlagBits.html">VkImageUsageFlags</a>
usage</code> field in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html)
similar to the equivalent field for buffers. In addition to the
same transfer source and destination flags, the major flags allow
the usage of the image as a color or resolve
(`VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT`), depth/stencil
(`VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT`), or input
(`VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT`) attachment.

There's also `VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT`, which
means that memory allocated for the image will use the
`VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` flag (see "Memory
management"). Any image can be created with this flag as long as
it can be used to create a view suitable for use as a color,
resolve, depth/stencil, or input attachment.

##### Dimensionality

The dimensionality of an image is expressed by two fields in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html)—<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageType.html">VkImageType</a>
imageType</code> and <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkExtent3D.html">VkExtent3D</a>
extent</code>. `imageType` can be `VK_IMAGE_TYPE_1D`, `*2D`, or
`*3D`, and `extent` has `uint32_t` fields `width`, `height`, and
`depth`. The fields of `extent` describe how many [_texel
blocks_](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#texel-block-size)
are found in each dimension of the image.  `width` corresponds to
the first dimension, `height` to the second, and `depth` to the
third. Accordingly, if `imageType` is `VK_IMAGE_TYPE_1D`,
`extent.height` and `extent.depth` must be `1`; if it's
`VK_IMAGE_TYPE_2D`, just `extent.depth` must be `1`.

What the dimensionality actually means in terms of how the image
data is laid out in memory depends on the tiling (see "Tiling").
Perhaps more significantly, the dimensionality of an image
dictates what you can do with it; for example, only 2D images can
be drawn to the screen (as you might expect).

##### MIP levels

The field `uint32_t mipLevels` in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html)
describes how many "slots" should be made available in the image
for storing [MIP maps](https://en.wikipedia.org/wiki/Mipmap). It
must be at least `1`, and at most
⌊log<sub>2</sub>(max(`extent.width`, `extent.height`,
`extent.depth`))⌋ + 1.

As an example, for a 2D 3840x2160 image, we have

⌊log<sub>2</sub>(max(`extent.width`, `extent.height`, `extent.depth`))⌋ + 1 =<br>
⌊log<sub>2</sub>(max(3840, 2160, 1))⌋ + 1 =<br>
⌊log<sub>2</sub>(3840)⌋ + 1 ≃<br>
⌊11.90689⌋ + 1 =<br>
11 + 1 =<br>
12.

This is because the dimensions of each successive MIP map are
found by max(⌊dimension/2⌋,1).

It should be noted that all specifying `mipLevels` does is create
_space_ for the MIP maps. It's up to you to actually supply them.
You can copy your MIP maps into the right "slots" using
[`vkCmdCopyImage()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdCopyImage.html)
(see "Simple copying" under "Command buffers");
[`VkImageCopy`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCopy.html)
has
[`VkImageSubresourceLayers`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageSubresourceLayers.html)
fields, which allow you to specify a MIP level.

##### Layers

A `VkImage` can actually function as an _array_ of image data
sets instead of just a container for a single image's data. If
you want this, you can specify the number of elements, called
_layers_, that your image should contain with the field `uint32_t
arrayLayers` in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html).
`arrayLayers` must be at least `1` in all cases, but can be a
maximum of <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceLimits.html">VkPhysicalDeviceLimits</a>::maxImageArrayLayers</code> (`2048` on my hardware).

There are a variety of reasons why you might want to do this. One
of the most common is to make a [cube
map](https://en.wikipedia.org/wiki/Cube_mapping). You do this by
setting `imageType` to `VK_IMAGE_TYPE_2D`, enabling
`VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT` in `flags`, setting
`samples` to `VK_SAMPLE_COUNT_1_BIT`, making `extent.width` and
`extent.height` equal, and finally setting `arrayLayers` equal to
or greater than `6` (greater than allows you to make a cube
array—note that only multiples of 6 will actually specify cube
maps). You can then make a cube or cube array image view to it
(see "Image views").

An image can have more than one layer and more than one MIP
level. Each layer then has its own MIP maps—or perhaps each MIP
map has its own layers…a question for the ages (or for driver
developers depending on your level of whimsy). You can specify
each separately in
[`VkImageSubresourceLayers`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageSubresourceLayers.html).

##### Samples

Vulkan supports
[multisampling](https://en.wikipedia.org/wiki/Multisample_anti-aliasing),
an anti-aliasing technique used in rasterization in which each
primitive is sampled in several different nearby places for each
pixel, with all the resulting data being used to determine that
pixel's value. You can set up an image for this by setting
<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSampleCountFlagBits.html">VkSampleCountFlagBits</a>
samples</code> to a value other than `VK_SAMPLE_COUNT_1_BIT` in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html)
(see "Multisampling" for the details).

Note that there are a variety of limitations in place when doing
this. `imageType` must be `VK_IMAGE_TYPE_2D`, `flags` must not
contain `VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT`, `mipLevels` must
be `1`, and `tiling` must be `VK_IMAGE_TILING_OPTIMAL`.

##### Tiling

<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageTiling.html">VkImageTiling</a>
tiling</code> in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html)
is used to control how the texel blocks of the image are laid out
in memory. It has two possible values, `VK_IMAGE_TILING_OPTIMAL`
and `VK_IMAGE_TILING_LINEAR`. An optimally-tiled image is laid
out in memory in an implementation-defined way that is
(hopefully) efficient to access, whereas a linearly-tiled image
is laid out in row-major order, padding as necessary.

Linearly-tiled images have various restrictions on their use. In
particular, an image with `tiling` set to
`VK_IMAGE_TILING_LINEAR` must have `imagetype` set to
`VK_IMAGE_TYPE_2D`, `format` not set to any depth/stencil format,
`mipLevels` set to `1`, `arrayLayers` set to `1`, `samples` set
to `VK_SAMPLE_COUNT_1_BIT`, and `usage` set to only
`VK_IMAGE_USAGE_TRANSFER_SRC_BIT` and/or
`VK_IMAGE_USAGE_TRANSFER_DST_BIT`.

With all these limitations, why would you ever want to use a
linearly-tiled image? Well, if you think about it, you have no
other choice if you want to access a host-mapped image through a
pointer. As a side note, you should probably set `initialLayout`
to `VK_IMAGE_LAYOUT_PREINITIALIZED` if you're writing to an image
this way, as you'll see in the next section.

##### Initial layout

There is a field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageTiling.html">VkImageTiling</a>
initialLayout</code> in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html)
with two possible values: `VK_IMAGE_LAYOUT_UNDEFINED` and
`VK_IMAGE_LAYOUT_PREINITIALIZED`. `VK_IMAGE_LAYOUT_UNDEFINED` is
the general-purpose option. `VK_IMAGE_LAYOUT_PREINITIALIZED` is
meant to be used for linearly-tiled images destined to be
directly written to by the host; it tells the driver that nothing
needs to be done to the data before writing it to device memory.

##### Flags

<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateFlagBits.html">VkImageCreateFlags</a>
flags</code> is a sort of catchall parameter in
[`VkImageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageCreateInfo.html)
for things that aren't covered elsewhere.

`VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT` indicates that the image
can be viewed as a cube or a cube array, and
`VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT` indicates that the
image can be viewed as a 2D or 2D array image. We'll talk about
those more in "Image views".

`VK_IMAGE_CREATE_ALIAS_BIT`, when applied to two images created
with the same parameters and aliased to the same memory,
indicates that both images can interpret this memory consistently
with each other if the rules of memory aliasing are followed (see
"Memory management").

`VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT` indicates that the image can
be used to create an image view with a different format from the
image. `VK_IMAGE_CREATE_EXTENDED_USAGE_BIT` indicates that the
image can be created with usage flags that are not supported for
its format but are supported for a format that views created
from it can have. These are particularly relevant to swapchains
(see "Swapchains").

The others cover niche features, things based on
not-always-present device features or extensions, etc.; check the
spec for the details.

#### Image subresources

An image subresource is a single layer and MIP map. An image
subresource range is a set of contiguous layers and MIP maps.

### Sharing mode

One thing worth noting about both buffers and images is that
their `*CreateInfo`s have a
[`VkSharingMode`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSharingMode.html)
field that says whether or not the resource in question can be
accessed from more than one queue at a time. If you pick
`VK_SHARING_MODE_EXCLUSIVE`, you'll need to perform a queue
family ownership transfer (see "Queue family ownership transfer"
under "Memory barriers") in order to give access to a queue that
doesn't currently have it. If you pick
`VK_SHARING_MODE_CONCURRENT`, you won't have to worry about this,
but queue-based access to the resource is likely to be slower
than if `VK_SHARING_MODE_EXCLUSIVE` was used. Also, you'll need
to supply an array of queue indices corresponding to each queue
that needs to access the resource (`pQueueFamilyIndices` in the
`*CreateInfo`), which you can ignore if you pick
`VK_SHARING_MODE_EXCLUSIVE`.

## Memory management

This is a rather subtle and intricate part of the API—there's
more to it than meets the eye at first. We'll discuss the
important functions and then talk tactics.

The type `VkDeviceMemory` is an opaque handle used by Vulkan to
represent a block of memory on the graphics device. You can use
it to allocate device memory via
[`vkAllocateMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateMemory.html),
which takes a logical device to allocate memory on, a pointer to
a `VkDeviceMemory`, and a
[`VkMemoryAllocateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkMemoryAllocateInfo.html), 
which says how much memory to allocate in the form of a
`VkDeviceSize` and which _type_ of device memory to allocate from.

You might remember waaaaaay back in "Physical devices" when we
mentioned using
[`vkPhysicalDeviceMemoryProperties2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceMemoryProperties2.html)
to get a sense of how much physical memory a device has, or how
much of it is in use at the moment. Well, this is that function's
time to shine. It will tell you which types of memory are
available on the physical device you're using. Let's take a look
at what
[`vulkaninfo`](https://vulkan.lunarg.com/doc/view/latest/linux/vulkaninfo.html)
says about that for my card:

```
VkPhysicalDeviceMemoryProperties:
=================================
...
memoryTypes: count = 11
    memoryTypes[0]:
        heapIndex     = 1
        propertyFlags = 0x0000: count = 0
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[1]:
        heapIndex     = 1
        propertyFlags = 0x0000: count = 0
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                color images
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[2]:
        heapIndex     = 1
        propertyFlags = 0x0000: count = 0
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_D16_UNORM
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[3]:
        heapIndex     = 1
        propertyFlags = 0x0000: count = 0
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_X8_D24_UNORM_PACK32
                FORMAT_D24_UNORM_S8_UINT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[4]:
        heapIndex     = 1
        propertyFlags = 0x0000: count = 0
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_D32_SFLOAT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[5]:
        heapIndex     = 1
        propertyFlags = 0x0000: count = 0
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_D32_SFLOAT_S8_UINT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[6]:
        heapIndex     = 1
        propertyFlags = 0x0000: count = 0
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_S8_UINT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[7]:
        heapIndex     = 0
        propertyFlags = 0x0001: count = 1
            MEMORY_PROPERTY_DEVICE_LOCAL_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                color images
                FORMAT_D16_UNORM
                FORMAT_X8_D24_UNORM_PACK32
                FORMAT_D32_SFLOAT
                FORMAT_S8_UINT
                FORMAT_D24_UNORM_S8_UINT
                FORMAT_D32_SFLOAT_S8_UINT
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[8]:
        heapIndex     = 1
        propertyFlags = 0x0006: count = 2
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[9]:
        heapIndex     = 1
        propertyFlags = 0x000e: count = 3
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
            MEMORY_PROPERTY_HOST_CACHED_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[10]:
        heapIndex     = 2
        propertyFlags = 0x0007: count = 3
            MEMORY_PROPERTY_DEVICE_LOCAL_BIT
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
```

Good grief!! Now you're starting to see what I mean. Doesn't
`malloc()` seem like a waltz through the roses right now?

It gets crazier. You might think that once you've got all this
sorted out you can just allocate memory willy-nilly as you
please. Welp, that would be awful nice, but as it happens you're
recommend to
[suballocate](https://github.com/KhronosGroup/Vulkan-Guide/blob/master/chapters/memory_allocation.md#sub-allocation)
memory rather than just plain allocating it. That's for two
reasons—some platforms have very small values for
[`maxMemoryAllocationCount`](https://www.khronos.org/registry/vulkan/specs/1.2/html/vkspec.html#limits-maxMemoryAllocationCount)
(like,
[4096](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxMemoryAllocationCount&platform=windows)
for most devices on
Windows—[4294970000](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxMemoryAllocationCount&platform=linux)
on Linux though), and because (de)allocating memory is likely to
be really slow in the driver.

Okay. Before we dive into this madness I have to mention that AMD
was nice enough to put out an MIT-licensed [Vulkan memory
management
library](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator)
that takes care of some of the busywork for you. It may or many
not be the ideal tool for your use case, and it's important to
understand the nitty-gritty stuff about this topic even if you do
use it, but just know that if this seems like a dizzying amount
of work to tackle for one small part of the API there is some
help out there. We'll come back to it later.

All right, pull up yer sleeves folks!!

### Memory types

Haha, I can't believe we're doing this. Anyway, when you call
[`vkPhysicalDeviceMemoryProperties2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceMemoryProperties2.html)
(or
[`vkPhysicalDeviceMemoryProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceMemoryProperties.html),
w/e), you get an array of
[`VkMemoryType`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkMemoryType.html)s, which tell you about
the types of memory available on the device (surprise, surprise).
These have the index of the memory heap the memory type in
question corresponds to, and also a bitmask of
[`VkMemoryPropertyFlagBits`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkMemoryPropertyFlagBits.html)
which gives you a sense of what the memory type is good for.

Oh wait, we didn't even mention memory heaps! Haha, okay. _Memory
heaps_ are areas of memory visible to the device in question.
They may be _device local_ (in the actual physical memory on the
device) or _host local_ (in RAM or w/e, you know)—what makes them
"memory heaps" to Vulkan is that the device can see them. Vulkan
also knows about which of the memory heaps the host can see, so
all in total we have three posibilities:

* _Device local_ memory that the host cannot see,
* _Device local, host visible_ memory, which is what you would
  think, and
* _host local, host visible_ memory which is host memory the
  device can see.

Not all three types exist on all devices. Some may have only one
(if the CPU is the device, for example).

Anyway, this is part of what a memory type tells us about. It
also tells us if the memory is

* _host coherent_, meaning that it isn't necessary to flush host
  writes to this area of memory or make device writes to it
  visible to the host,
* _host cached_, meaning that the memory's cache is stored in
  host memory, and
* _lazily allocated_, meaning that only the device can access the
  memory.

There's some other stuff from not-always-present features and
extensions and things but those are the main points.

Let's return to that `vulkaninfo` output but sans the "usable
for" stuff and plus the contents of `memoryHeaps`:

```
VkPhysicalDeviceMemoryProperties:
=================================
memoryHeaps: count = 3
    memoryHeaps[0]:
            size   = 6442450944 (0x180000000) (6.00 GiB)
            budget = 3044737024 (0xb57b0000) (2.84 GiB)
            usage  = 0 (0x00000000) (0.00 B)
            flags: count = 1
                    MEMORY_HEAP_DEVICE_LOCAL_BIT
    memoryHeaps[1]:
            size   = 50523119616 (0xbc369a000) (47.05 GiB)
            budget = 50523119616 (0xbc369a000) (47.05 GiB)
            usage  = 0 (0x00000000) (0.00 B)
            flags: count = 0
                    None
    memoryHeaps[2]:
            size   = 257949696 (0x0f600000) (246.00 MiB)
            budget = 245170176 (0x0e9d0000) (233.81 MiB)
            usage  = 12779520 (0x00c30000) (12.19 MiB)
            flags: count = 1
                    MEMORY_HEAP_DEVICE_LOCAL_BIT
memoryTypes: count = 11
    memoryTypes[0–6]:
        heapIndex     = 1
        propertyFlags =
            None
    memoryTypes[7]:
        heapIndex     = 0
        propertyFlags =
            MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    memoryTypes[8]:
        heapIndex     = 1
        propertyFlags =
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
    memoryTypes[9]:
        heapIndex     = 1
        propertyFlags =
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
            MEMORY_PROPERTY_HOST_CACHED_BIT
    memoryTypes[10]:
        heapIndex     = 2
        propertyFlags =
            MEMORY_PROPERTY_DEVICE_LOCAL_BIT
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
```

Excusing my rather untoward reveal of my hardware's
characterstics, we can see that heap 1 is host memory, heap 0 is
the main block of device memory, and heap 2 is a relatively small
staging area of sorts in device memory that is visible to the
host. Keep in mind that your hardware may be different—try
running
[`vulkaninfo`](https://github.com/KhronosGroup/Vulkan-Tools/blob/master/vulkaninfo/vulkaninfo.md#running-vulkan-info)
and see.

You might be curious as to why the elements of `memoryTypes[]`
are ordered the way they are. As it happens, there is a specific
reason, or rather set of reasons. They're ordered from least to
most featureful, and from fastest to slowest aside from that,
more or less. Being precise, if:

* memory type __X__ has a smaller number of `propertyFlags`
  than memory type __Y__, or
* __X__ and __Y__ have the same number of `propertyFlags` but
  __X__ belongs to a faster heap, or
* __Y__ is _device coherent_ or _device uncached_ (i.e.  it's
  slow) and __X__ is not,

then __X__ is given a smaller index than __Y__.

The basic idea here is that, when you need to store something in
memory, you can loop through `memoryTypes[]` from the beginning
looking for a type that fits your requirements and you'll get the
fastest type that supports them as exactly as possible.

Let's consider an example. Say we have a device of some sort and
a buffer of some sort:

```cpp
VkDevice device;
VkBuffer buffer;
```

We'd like this buffer to represent a block of device memory.
First, we need to call `vkGetBufferMemoryRequirements()` for it:

```cpp
VkMemoryRequirements buf_mem_reqs;
vkGetBufferMemoryRequirements(device, buffer, &buf_mem_reqs);
```

`buf_mem_reqs` has a bitmask field `memoryTypeBits` that has a
bit set for each index of `memoryTypes[]` corresponding to a
memory type that can support our `buffer`.

Let's see what happens if we just look for a device local memory
type:

```cpp
// in practice we would have done this part long ago, but
// just for demonstration...
VkPhysicalDevice phys_dev; // the device in use
VkPhysicalDeviceMemoryProperties phys_dev_mem_props;
vkGetPhysicalDeviceMemoryProperties(phys_dev, &phys_dev_mem_props);

std::optional<uint32_t> find_mem_type(uint32_t supported_types,
                                      VkMemoryPropertyFlags reqs)
{
    for (uint32_t i = 0; i < phys_dev_mem_props.memoryTypeCount; ++i) {
        bool type_supported = (1 << i) & supported_types;
        bool fits_reqs = (memoryTypes[i].propertyFlags & reqs) == reqs;

        if (type_supported && fits_reqs) {
            return i;
        }
    }

    return std::nullopt;
}

auto type_ndx = find_mem_type(buf_mem_reqs.memoryTypeBits,
                              VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
```

If you glance back up at `memoryTypes`, you'll see that
`type_ndx.value()` will be `7`, corresponding to `memoryHeap[0]`,
provided that it supports our `buffer`. That heap is purely
device local—in other words, it's not host visible. That means we
can't map it to host memory, so we can't write to it directly
from the host. That may or may not matter; if it does matter, we
could try adding `VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` to our
requirements:

```cpp
VkMemoryPropertyFlags reqs = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
                             | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
type_ndx = find_mem_type(buf_mem_reqs.memoryTypeBits, reqs);
```

This time, provided it supports our `buffer`, we'll get `10` for
`type_ndx.value()`, corresponding to `memoryHeaps[2]`. That's the
relatively small "staging area" on the graphics card.

Also note that if we had just specified
`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT`, we would get
`memoryTypes[8]`, corresponding to `memoryHeaps[1]`, host memory.
However, `memoryTypes[8]` is not cached on the host. If it was,
host accesses to it would be faster, so we could specify
`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
VK_MEMORY_PROPERTY_HOST_CACHED_BIT` and we would get
`memoryTypes[9]` instead.

You can see that what makes the most sense is to first specify
the ideal characteristics of the memory type you want and see if
you get anything back. If not, you can try trimming them down
until you do get what you want. This allows you to get the best
possible memory type in the lowest number of steps.

```cpp
std::array desired_props_list {
    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
    | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,

    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,

    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
};

for (auto&& props : desired_props_list) {
    type_ndx = find_mem_type(buf_mem_reqs.memoryTypeBits, props);

    if (type_ndx.has_value()) {
        break;
    }
}

// first pass:
//     !type_ndx.has_value()
// second pass:
//     type_ndx.value() == 10
```

You may be feeling anxious at this point about the possibility of
not being able to find a memory type that fits even your minimum
requirements at some point in time. Luckily, there are some
guarantees. You are promised at least one memory type with both
`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` and
`VK_MEMORY_PROPERTY_HOST_COHERENT_BIT` set, and at least one
memory type with `VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT` set.
That's why `VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT` by itself came
last in `desired_props_list` just now.

A plain, unqualified `VkBuffer` is likely to be compatible with
any of the available memory types. However, the same is not
necessarily true of `VkImage`s, which tend to only be compatible
with certain types of memory based on their tiling and format.
That's what was being shown in that "usable for" section
earlier—let's bring that back:

```
memoryHeaps: count = 3
    memoryHeaps[0]:
            size   = 6442450944 (0x180000000) (6.00 GiB)
            budget = 3044737024 (0xb57b0000) (2.84 GiB)
            usage  = 0 (0x00000000) (0.00 B)
            flags: count = 1
                    MEMORY_HEAP_DEVICE_LOCAL_BIT
    memoryHeaps[1]:
            size   = 50523119616 (0xbc369a000) (47.05 GiB)
            budget = 50523119616 (0xbc369a000) (47.05 GiB)
            usage  = 0 (0x00000000) (0.00 B)
            flags: count = 0
                    None
    memoryHeaps[2]:
            size   = 257949696 (0x0f600000) (246.00 MiB)
            budget = 245170176 (0x0e9d0000) (233.81 MiB)
            usage  = 12779520 (0x00c30000) (12.19 MiB)
            flags: count = 1
                    MEMORY_HEAP_DEVICE_LOCAL_BIT
memoryTypes: count = 11
    memoryTypes[0]:
        heapIndex     = 1
        propertyFlags =
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[1]:
        heapIndex     = 1
        propertyFlags =
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                color images
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[2]:
        heapIndex     = 1
        propertyFlags =
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_D16_UNORM
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[3]:
        heapIndex     = 1
        propertyFlags =
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_X8_D24_UNORM_PACK32
                FORMAT_D24_UNORM_S8_UINT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[4]:
        heapIndex     = 1
        propertyFlags =
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_D32_SFLOAT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[5]:
        heapIndex     = 1
        propertyFlags =
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_D32_SFLOAT_S8_UINT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[6]:
        heapIndex     = 1
        propertyFlags =
            None
        usable for:
            IMAGE_TILING_OPTIMAL:
                FORMAT_S8_UINT
            IMAGE_TILING_LINEAR:
                None
    memoryTypes[7]:
        heapIndex     = 0
        propertyFlags =
            MEMORY_PROPERTY_DEVICE_LOCAL_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                color images
                FORMAT_D16_UNORM
                FORMAT_X8_D24_UNORM_PACK32
                FORMAT_D32_SFLOAT
                FORMAT_S8_UINT
                FORMAT_D24_UNORM_S8_UINT
                FORMAT_D32_SFLOAT_S8_UINT
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[8]:
        heapIndex     = 1
        propertyFlags =
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[9]:
        heapIndex     = 1
        propertyFlags =
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
            MEMORY_PROPERTY_HOST_CACHED_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
    memoryTypes[10]:
        heapIndex     = 2
        propertyFlags =
            MEMORY_PROPERTY_DEVICE_LOCAL_BIT
            MEMORY_PROPERTY_HOST_VISIBLE_BIT
            MEMORY_PROPERTY_HOST_COHERENT_BIT
        usable for:
            IMAGE_TILING_OPTIMAL:
                None
            IMAGE_TILING_LINEAR:
                color images
                (non-transient)
```

So if you look back at "Formats" under "Images" you might recall
us talking through these formats back there. Perhaps you even
recall allusions to the fact that not all types of memory support
all image formats. Well, here it is, in all it's "glory"
(horror?).

Oh, and you might also recall from there that "color images" in
this chart is `VK_FORMAT_R8G8B8A8_UNORM`.

You might note also that the formats are split up by tiling
(check out "Tiling" under "Images" if you're not sure what this
is about). This helps to clarify the role of
`memoryTypes[0`–`6]`—these are for storing non-host-visible
buffers and optimally-tiled images in host memory. If you guessed
that these are for the device to use as "overflow" memory if
device memory is exhuasted, [you're
correct!](https://developer.nvidia.com/what%E2%80%99s-your-vulkan-memory-type)
(Of course, actually making that happen is your job in Vulkan,
just like most everything else.)

Unsurprisingly, also, all the types that _are_ host visible only
support buffers and linearly-tiled images. This figures, for the
same reason that it wouldn't make sense to host-map an
optimally-tiled image—you wouldn't be able to make heads or tails
of it, at least not naïvely.

The "non-transient" stuff means that images with the applicable
tiling can't have `VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT` set,
i.e. their memory can't be lazily allocated. It's not surprising
that this would be specified for linearly-tiled images, as
lazily-allocated memory has to be both device visible and not
host visible. Also, since this would mean that the device would
allocate and write to the image's memory as needed, it wouldn't
make sense for the image to be linearly-tiled, as that's mainly
meant for images that need to be accessed directly by the host.

As we mentioned back in "Logical devices", you can use
[`vkGetImageMemoryRequirements()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetImageMemoryRequirements.html)
to gather this data yourself. Of course, if you followed the plan
we outlined there, you'll already have it cached.

### Allocating memory

This part is relatively simple by comparison. The main way to
allocate device memory in Vulkan is with the function
[`vkAllocateMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateMemory.html).
This takes parameters in a
[`VkMemoryAllocateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkMemoryAllocateInfo.html),
which specifies the number of bytes to allocate and the index of
a memory type to allocate memory from (see above).

The memory itself is represented by an opaque handle of type
[`VkDeviceMemory`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceMemory.html).
By itself, this is a kind of vague bag o' bits somewhere you
can't do much with. You have to bind, map, etc. the memory in
order to work with it.

To free memory, use
[`vkFreeMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkFreeMemory.html).
You have to ensure that the memory is not still in use by the
device (e.g. by being attached to a pending command buffer).
However, it's okay to free memory that is still bound to a
resource as long as you won't make any use of those resources
afterwards. If there are still resources bound to it, the memory
may not truly be relinquished by the device until the associated
resources are destroyed, so keep that in mind if you're not
getting your bytes back when you call `vkFreeMemory`.

### Mapping memory

The memory wrapped by `VkDeviceMemory` objects is not directly
accessible by the host after allocation. You can make it directly
accessible in some cases with
[`vkMapMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkMapMemory.html).
This has you to specify both an offset and a range of bytes to
map within the memory object (you can specify `VK_WHOLE_SIZE` for
the range to map from the offset to the end of the allocation),
and it sets up a regular ol' pointer you can use to access the
memory through.

If you're wondering what I mean by "in some cases," you may
recall from the previous discussion of memory types that if a
memory type does not have `VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT`
set then memory allocated from it cannot be used with
`vkMapMemory()`. You might also recall that host visible memory
can't hold optimally-tiled images, and that in my environment
there's only a smallish block of host-visible device memory (246
MiB out of the whole 6 GiB).

All of this means that getting data on and off the device isn't
necessarily as straightforward as just mapping some device memory
to the host and accessing it. AMD
[recommends](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/usage_patterns.html)
(for graphics hardware in general) that host-visible device
memory be used for resources that will be updated frequently by
the host and read frequently by the device (like every frame).
They also recommend that this memory be written to using
`memcpy()` from the host and also that it not be randomly
accessed (as this is likely to be very slow).  Furthermore, if
there is memory written to by the device that needs to be read
afterwards by the host, they recommend that the device write to
both host-visible and host-cached memory (which in my environment
would end up being host memory). For resources written by the
host and read by the device that are too large to fit comfortably
in host-visible device memory, they recommend writing them in
host memory and transferring them into the main block of device
memory separately. Of course, none of this applies to integrated
graphics—you can do everything in host memory in that case
because there is no real device memory. In short, when to use
`vkMapMemory()` depends on your application's needs and the
hardware it's running on, like many things in Vulkan.

`vkMapMemory()` does not check to see if the memory is currently
in use before providing the pointer to it. You need to take care
of that yourself—see "Synchronization" for more on this. Same
goes for access to the memory while it is mapped.

Naturally, while a memory object is host-mapped, you shouldn't
call `vkMapMemory()` on it again while it's still mapped.

To unmap mapped memory, use
[`vkUnmapMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkUnmapMemory.html).
You might be wondering here if you can leave some memory
persistently mapped for the lifetime of your application. The
answer is yes, but with the
[caveat](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/memory_mapping.html#memory_mapping_persistently_mapped_memory)
that on Windows <10 the contents of device-local host-mapped
memory may be migrated to host memory when `vkQueueSubmit()` or
`vkQueuePresentKHR()` are called, which is obviously bad for
performance. If you need to support Windows 7 or 8, you may want
to map device-local memory only as long as you need to on those
OSes.

If the mapped memory comes from a memory type without
`VK_MEMORY_PROPERTY_HOST_COHERENT_BIT` set, flushing and
invalidating the memory also needs to be managed by the host to
ensure that accesses to it are visible to both the host and
device. There are two functions provided for this purpose,
[`vkFlushMappedMemoryRanges()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkFlushMappedMemoryRanges.html)
and
[`vkInvalidateMappedMemoryRanges()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkInvalidateMappedMemoryRanges.html).
`vkFlushMappedMemoryRanges()` ensures that host writes to the
specified memory ranges are made visible to the device, while
`vkInvalidateMappedMemoryRanges()` ensures that device writes to
the specified memory ranges are made visible to the host. It's
worth noting that unmapping non-host-coherent memory does not
flush it, nor does mapping non-host-coherent memory automatically
invalidate it—you have to take care of these things while you're
mapping and unmapping the memory.

### Binding resources to memory

Resources (images and buffers) are not immediately associated
with an actual block of memory when they're first created. Before
they can be used to create views, update descriptor sets, or
record commands in a command buffer, they need to be contiguously
_bound_ to a memory object (it's a bit different with sparse
resources but we'll talk about that elsewhere since it's not a
universal feature).

To bind a resource, you have a couple options. The first is to
use
[`vkBindBufferMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkBindBufferMemory.html)
or
[`vkBindImageMemory()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkBindImageMemory.html),
both of which just require you to specify an offset into the
memory at which to start binding the resource. However, you can
also use
[`vkBindBufferMemory2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkBindBufferMemory2.html)
and
[`vkBindImageMemory2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkBindImageMemory2.html),
which allow you to perform multiple bindings in one call; this is
likely to be more efficient when you have the opportunity.

Once bound, a resource cannot be unbound without destroying it.

You might recall our brief explorations of the functions
[`vkGetImageMemoryRequirements()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetImageMemoryRequirements.html)
and
[`vkGetBufferMemoryRequirements()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetBufferMemoryRequirements.html).
You can use these to determine the type, size, and alignment
requirements of the resource to guide you in determining where in
memory to bind them.

### Sub-allocating

As we touched on briefly, it's
[recommended](https://github.com/KhronosGroup/Vulkan-Guide/blob/master/chapters/memory_allocation.md#sub-allocation)
that you sub-allocate memory for most resources rather than
performing a unique allocation for each one. AMD's Adam Sawicki
[recommends](https://ubm-twvideo01.s3.amazonaws.com/o1/vault/gdc2018/presentations/Sawicki_Adam_Memory%20management%20in%20Vulkan.pdf)
allocating memory in 256 MiB blocks unless the heap is <= 1 GiB,
in which case he recommends using a block size of heap size / 8.
He also recommends not performing allocations in the main loop at
all if possible, and in a background thread if you absolutely
need to, because of how slow it is.

It should be fairly easy to see how you would do this after
everything we've covered. After allocating a block of memory, you
can bind multiple resources to it by keeping track of their sizes
and offsets.

Note that there is a value
`VkPhysicalDeviceLimits::bufferImageGranularity` that specifies
the granularity at which linear and non-linear (e.g.
optimally-tiled) resources need to be placed in memory to avoid
aliasing. It's specified in bytes and is always a power of 2 (in
my environment it's 1 KiB).

While you're at it, it's not _exactly_ sub-allocation, but Nvidia
[recommends](https://developer.nvidia.com/vulkan-memory-management)
that you make small numbers of large buffers and store different
kinds of data in them by offset, rather than creating many small
buffers for different uses. In other words, you should apply the
same pattern to buffer management that you do to memory
management. This helps to avoid overhead on the host from having
tons of small objects around.

### Putting it all together

Okay!! We pretty much have all the information we need here to
write a good Vulkan allocator. We've covered a lot of ground,
though, so I thought it might be nice to sum it all up.

There are a couple of fundamental guiding principles you can
apply to figure out how to make the best decisions when designing
your allocator. One is that the host and device are fast at
accessing their own memory and slow at accessing each other's
memory (assuming the system has discrete graphics). The other is
that allocating memory is always slow.

Anyway, you first want to identify the largest memory heap with
`VK_MEMORY_HEAP_DEVICE_LOCAL_BIT` set, and then look for the most
versatile memory type that corresponds to that heap. By
"versatile," I don't mean the one with the most property flags
set, but rather the one that supports the widest variety of
formats. Your main pool of video memory will come from here.

Allocate one or more large blocks of memory from this memory
type. "Large" probably means 256 MiB, unless the heap in question
is <= 1 GiB, in which case "large" means heap size / 8. If you
know how much memory your application will use over its whole
run, you can allocate all that you'll need here, which will save
you from having to perform allocations from the main loop. Also,
you don't _have_ to allocate 256 MiB of memory if you know for
sure that your application needs less—that's just a good rule of
thumb.

If you have data that the host needs to write and the device
needs to read that changes often, like every frame, look for a
memory type with `VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT` and
`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` set. If you don't find such
a type, look for one that has both
`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` and
`VK_MEMORY_PROPERTY_HOST_CACHED_BIT`, and failing that,
`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` and
`VK_MEMORY_PROPERTY_HOST_COHERENT_BIT` (which is guaranteed to be
there). Once you've picked a type, allocate a block of memory
from it if it's a different type than the one you used for your
main pool (using the same guidelines from the previous
paragraph). Bind a buffer to it, whatever size makes sense. Also,
map it, unless it's in device memory and you're on Windows <10.

If you have data written by the host and read by the device that
only needs to change occasionally or not at all, look for a
memory type with `VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` and
`VK_MEMORY_PROPERTY_HOST_CACHED_BIT`, and failing that,
`VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT` and
`VK_MEMORY_PROPERTY_HOST_COHERENT_BIT`. If you haven't already
allocated memory from this type, allocate a block of memory from
it (again, same guidelines). You'll use this to stage large
resources for transference into your video memory pool. If some
of this is non-image data, bind a buffer to part of this
allocation for it, leaving space for images.

When you need to start moving things around in memory, use the
following guidelines:

* If it's data that the host writes and the device reads…
    * …if it needs to be updated frequently, mark out space for
      it in the buffer you reserved for this purpose and write it
      through a mapped pointer (map and unmap the memory as
      needed if you're on Windows <10). If the buffer's memory is
      device-local, have the device read directly from this
      buffer instead of transferring the data elsewhere. If it's
      host-local and you have a large set of data (like if you're
      working with a texture), transfer it from the buffer into
      your main video memory pool before having the device use
      it.
    * …if it doesn't need to be updated frequently, write it to
      your host-local "staging pool", creating and binding an
      image resource if needed. Then schedule a transfer for it
      into your video memory pool.
* If it's data that the device writes and the host reads, have
  the device write it to the same pool you use for
  frequently-updated host-written data. Remember the flushing and
  invalidating stuff if the memory is not host-coherent.
* If it's data the device reads and writes and the host accesses
  little or not at all, work with it entirely in your video
  memory pool.

Query resources for their size and alignment requirements before
binding them, and keep track of where they are in the pools using
that information. At some point, you may run out of usable memory
somewhere; you can then allocate another block for that pool in a
background thread. Try to stick to having 20–30% of device memory
free (remember other applications need it too). If you run out of
device memory, you can use your host-side memory pool as
"overflow" video memory (just note that this may cause
performance degredation). Defragmenting a pool may help free up
larger blocks of memory (and you may be able to do it in a
background thread if you're strategic about it, or do this in
small ways as you go so the problem never gets out of hand).

Obviously, implementing all this is not exactly a walk in the
park, so you may want to use AMD's [Vulkan Memory
Allocator](https://gpuopen.com/vulkan-memory-allocator/) to save
yourself some work. We'll talk about that next.

### AMD's Vulkan Memory Allocator

AMD has a free (MIT-licensed) library available called Vulkan
Memory Allocator (VMA). It doesn't do _everything_ memory-related
for you, but it lets you manage memory at a bit of a higher level
than Vulkan has you doing out-of-the-box. Here's the [source
repo](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator)
and
[documentation](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/).
We'll talk broadly about how it works and whether or not you
might want to use it.

It comes as a header-only library. Thankfully it has no
dependencies aside from Vulkan. It's written in C++ but exposes a
C interface, although this does mean that you need to use a C++
compiler to compile the part of your code where you include the
full implementation of the library (you could also just compile
it into a regular, non-header-only library if you're writing a C
application and need to use a C compiler). It assumes by default
that you're statically linking with Vulkan, but you can configure
it otherwise and also hand it the function pointers it needs if
you're loading Vulkan functions at runtime. (See
[here](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/quick_start.html)
and
[here](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/configuration.html)
for more on these topics.)

After creating a logical device, you can create a
[`VmaAllocator`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/struct_vma_allocator.html),
which is the main object in the library. You create it in
conjunction with a
[`VmaAllocatorCreateInfo`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/struct_vma_allocator_create_info.html);
this allows you to set the maximum number of bytes to allocate
from a given heap and how many frames you need to keep track of
resources for, among other things.

VMA provides its own functions for creating and destroying
resources,
[`vmaCreateBuffer()`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/vk__mem__alloc_8h.html#ac72ee55598617e8eecca384e746bab51)
/
[`vmaCreateImage()`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/vk__mem__alloc_8h.html#a02a94f25679275851a53e82eacbcfc73)
and
[`vmaDestroyBuffer()`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/vk__mem__alloc_8h.html#a0d9f4e4ba5bf9aab1f1c746387753d77)
/
[`vmaDestroyImage()`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/vk__mem__alloc_8h.html#ae50d2cb3b4a3bfd4dd40987234e50e7e).
Whether creating buffers or images, VMA uses a struct
[`VmaAllocationCreateInfo`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/struct_vma_allocation_create_info.html#a6272c0555cfd1fe28bff1afeb6190150)
to get parameters for the allocation. This allows you to set
required and preferred `VkMemoryPropertyFlags` and a bitmask of
`memoryTypeBits` to specify which memory types are acceptable if
desired. However, it also has its own usage enum,
[`VmaMemoryUsage`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/vk__mem__alloc_8h.html#aa5846affa1e9da3800e3e78fae2305cc),
which lets you specify how the host and device will need to
access the memory. All of these are optional; any that are
specified will place limitations on which pool the allocator
uses. You can also specify the
[`VmaPool`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/struct_vma_pool.html)
manually if you want. It also provides `vmaBind*` functions that
you can use to bind resources you've created through the Vulkan
API.

It has some convenience functions for mapping memory. They're not
that different from the Vulkan interface, but they're a bit safer
(it's okay to call
[`vmaMapMemory()`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/vk__mem__alloc_8h.html#ad5bd1243512d099706de88168992f069)
on an already-mapped memory object, for instance). It does take
care of basic synchronization and has a flag you can set if you
want to map the memory persistently, but you still need to take
care of flushing and invalidating the memory if it's not
host-coherent. See ["Memory
mapping"](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/memory_mapping.html)
in the VMA docs for more info.

There's no special support for binding a single large buffer and
storing different kinds of data in it by offset. You can allocate
such a buffer with VMA, but you have to take care of managing it
afterwards.

When allocating a new block, VMA will automatically allocate a
smaller block than the default size if allocating a default-sized
block would go over the memory budget (unless the resource in
question is too large).

It permits memory aliasing but doesn't really provide special
support for it.

It can defragment both host and device memory. However, you have
to destroy and recreate all the resources within that memory as
well as recreating their views and updating any of their
associated descriptors. It can do this in a background thread,
but since you can't really do anything with the memory in
question while defragmentation is happening, there might not
be much useful work you can do in parallel depending on your
application.

It has a concept called "lost allocations" that can automatically
"abandon" resources that are guaranteed not to be needed anymore.
This can help ensure that available memory is not exhausted. It
does this based on how many frames have passed since the resource
was last accessed. You have to tell it when a new frame starts,
mark resources as "losable," and query resources at the start of
each frame to see if they're still available. See ["Lost
allocations"](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/lost_allocations.html)
in the VMA docs for more info.

So, should you use it? That's a call you have to make. One of the
biggest complaints you might have about it is that it doesn't
necessarily save you _that_ much work on top of what Vulkan has
you do, and there are always costs associated with bringing in
any dependency. On the other hand, much of what it does do are
things that the average Vulkan application would end up
implementing in largely the same way, and it's very flexible, so
you can probably get it to work close to how your code would have
done in the places where you do use it (unless your application
is very unusual).

My hunch is that rather "middleweight" Vulkan applications will
get the most out of it—those that have a fair bit of data flying
around but don't require super-intensive optimization to run
acceptably. Really heavy applications that need to squeeze every
last cycle they can out of the hardware will probably end up
pushing the library out of the way in many areas to do things
themselves, and thus may not actually make much use of it.
Lighter applications may be able to predict quite precisely how
much memory they'll need and where and thus won't need a lot of
complicated logic around memory management (although they may
still be able to save on boilerplate by using VMA). These are all
just guesses on my part, though—you know your application best.

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
in **B∩S₂**. Any other operations are not synchronized. This
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
a complex chain of batches. For this reason, the Khronos Group
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

Vulkan pipelines represent a set of operations for the GPU to
perform. They come in three variants: _graphics_, _compute_, and
_ray tracing_. They are where you attach your shaders, and where
you configure the interactions between shader invocations.

From a certain perspective, the pipeline is the "heart" of
Vulkan. The rest of the API could be viewed as setup, teardown,
input, and output handling around the pipelines, which is where
the "actual work" takes place. There are obviously other ways of
looking at Vulkan too, but if you're trying to figure out how to
do something concrete with Vulkan and feeling a bit overwhelmed
by the size of the API, meditating on pipelines for a while can
help bring everything into focus.

### Initialization

The creation of each variant has unique aspects which we will
cover separately. However, they also have aspects in common. For
one, they all require a logical device and support custom
allocation callbacks. Their other common aspects are more
particular to pipelines.

All pipelines can be created in conjunction with a pipeline cache
(see "Caches" below). This can be used to optimize the
creation of a group of pipelines that have some things in common.
It can also be used to cache the results of pipeline creations
between application runs.

Each pipeline takes a
[`VkPipelineCreateFlagBits`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineCreateFlagBits.html)
bitmask as a parameter in its initialization. These are involved
in setting up pipeline derivation (see "Derivatives"
below). They also allow disabling optimization, which
may speed up pipeline creation at the cost of slowing its
execution time. Other than that, the available flags come from
extensions, are specific to a single pipeline variant, etc.

The struct type
[`VkPipelineShaderStageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineShaderStageCreateInfo.html)
is involved in the creation of all pipelines. This is where you
can join a
[`VkShaderModule`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkShaderModule.html),
containing shader code, to a pipeline stage. Graphics and ray
tracing pipelines are made with an array of these, whereas
compute pipelines use only one; this reflects how graphics and
ray tracing pipelines have multiple stages whereas compute
pipelines do not. A single instance is made with a
[`VkShaderStageFlagBits`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkShaderStageFlagBits.html),
which is used across the API to describe shader stages, but its
value here must describe a single shader stage (i.e. it cannot be
`VK_SHADER_STAGE_ALL_GRAPHICS` or `VK_SHADER_STAGE_ALL`). You are
also required to specify the name of the entry point for the
shader (see "Shaders"). You can optionally pass an array of
[`VkSpecializationInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSpecializationInfo.html)s,
which allow constant values in a shader module to be specified at
pipeline creation time (see "Specialization constants" below).
If the
[`VK_EXT_subgroup_size_control`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_EXT_subgroup_size_control.html)
extension is enabled, the
[`VkPipelineShaderStageCreateFlagBits`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineShaderStageCreateFlagBits.html)
parameter can be used to control aspects of the stage's subgroup
size variance (see "Subgroup" under "Shaders").

Pipeline initilization also requires a valid
[`VkPipelineLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineLayout.html),
which is used to make resource descriptors and push constants
available to shaders in the pipeline (see "Resource
descriptors").

All the pipeline creation functions take an array of their
respective `*CreateInfo` structures, which allows pipeline
creation to be done in batches. This allows pipeline creation
calls to be kept to a minimum. There are optional parameters
available in the `*CreateInfo`s for supplying a pipeline handle or
an index to another `*CreateInfo` in the array for the pipeline
to derive from (see "Derivatives").

When creating multiple pipelines at once, only the handles for
the pipelines that failed to be created will be set to
`VK_NULL_HANDLE`; the others will be valid. If any pipeline
creation fails despite valid arguments, the `VkResult` returned
by the creation function will indicate the reason.

Pipeline creation can be an expensive process. It may be
advisable to create uncached pipelines as early as possible in
your application, and to perform pipeline creation asynchronously
from rendering so as not to cause stuttering.

### Destruction

All pipelines are destroyed with
[`vkDestroyPipeline()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyPipeline.html).
Any submitted commands that refer to the pipeline in question
must have finished executing (see "Synchronization" for more on
how to ensure this).

### Caches

A _pipeline cache_ is meant to allow the reuse of work done in
the course of pipeline creation. That said, they are an
optimization mechanism that is used in an implementation-defined
way, and thus are not guaranteed by the spec to do much of
anything in particular. At the same time,
[AMD](https://gpuopen.com/performance/),
[Nvidia](https://developer.nvidia.com/blog/vulkan-dos-donts/),
[Samsung](https://developer.samsung.com/galaxy-gamedev/resources/articles/usage.html),
and
[Arm](https://github.com/ARM-software/vulkan_best_practice_for_mobile_developers/blob/master/samples/performance/pipeline_cache/pipeline_cache_tutorial.md)
have all recommended their use, so at least to the extent that
those articles are still current it's probably a safe bet that
you'll get a performance boost out of pipeline caches.

Pipeline caches are created via
[`vkCreatePipelineCache()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreatePipelineCache.html).
The associated
[`VkPipelineCacheCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineCacheCreateInfo.html)
structure is fairly simple. It has a
[`VkPipelineCacheCreateFlagBits`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineCacheCreateFlagBits.html)
parameter that supports only the flag
`VK_PIPELINE_CACHE_CREATE_EXTERNALLY_SYNCHRONIZED_BIT_EXT`, which
signals that the host will take care of synchronizing access to
the pipeline cache (the implementation _might_ use this
information to make access to the cache faster). It also has
optional parameters for supplying existing pipeline cache data,
i.e. if it was saved to disk during a prior application run.

To make use of a cache, its handle can be supplied during
pipeline creation; see "Initialization" above.

To retrieve the data from a pipeline cache, use
[`vkGetPipelineCacheData()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPipelineCacheData.html),
which can write the cache data to a caller-supplied address as a
string of bytes. The format of this data is largely
implementation-defined, but is required to begin with a header
supplying information about the device, driver version, etc. that
can be used to check whether or not the cache is compatible with
the current environment (see the link for details).

To destroy a pipeline cache, call
[`vkDestroyPipelineCache()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyPipelineCache.html).

### Derivatives

One pipeline can serve as the _parent_ of another, which is then
termed its _child_ or its _derivative_. Theoretically, this
allows part of the work used in creating the parent to be reused
in the creation of the child, making the creation of the child
more efficient. Like pipeline caches, though, the spec does not
currently describe what designating one pipeline as the child of
another actually accomplishes in concrete terms; it is left up to
the graphics driver to make use of this information however it
wishes (which might be not at all). What's more,
[Nvidia](https://developer.nvidia.com/blog/vulkan-dos-donts/),
[Samsung](https://developer.samsung.com/galaxy-gamedev/resources/articles/usage.html),
and
[Arm](https://github.com/ARM-software/vulkan_best_practice_for_mobile_developers/blob/master/samples/performance/pipeline_cache/pipeline_cache_tutorial.md)
have actively recommended against their use as of 2019, so unless
something has changed since then you may not see a performance
boost from using this feature.

To create a pipeline that can serve as the parent of another, set
the `VK_PIPELINE_CREATE_ALLOW_DERIVATIVES` flag during its
creation (see "Initialization" above for more on this).

To create a pipeline as the child of another, set the
`VK_PIPELINE_CREATE_DERIVATIVE` flag, and then either supply an
already-created pipeline handle _or_ an index to an
earlier-appearing `*CreateInfo` struct in the same call (see
"Initialization" above for more on this). If the handle parameter
is the unused one, it should be set to `VK_NULL_HANDLE`, and if
the index parameter is the unused one, it should be set to `-1`.

It is valid to set both `VK_PIPELINE_CREATE_ALLOW_DERIVATIVES`
and `VK_PIPELINE_CREATE_DERIVATIVE`, allowing a pipeline to serve
as both a parent and a child.

### Variants

#### Compute pipeline

Even though the graphics pipeline may well be the main pipeline
variant on your mind, the compute pipeline is simpler, so it's
worth exploring first to help get our bearings.

A compute pipeline is meant for performing abstract computation
on the GPU, apart from the complicated machinery of the graphics
pipeline. This can provide better performance than using a
graphics pipeline if the desired operations don't need to produce
a visual image directly. Despite their abstract nature, they are
still used in the context of graphics work for "purely
mathematical" data transformations, such as effects applied to an
already-rendered image. They can also be used for other
applications, such as scientific simulations.

GPUs excel at linear algebra, owing to their highly parallel
nature and large number of cores. If you need to perform a
relatively simple operation over a large matrix, doing it on the
GPU with a compute shader may be faster than doing it on the CPU,
even if the CPU code is properly multithreaded. Furthermore, the
shader code needed to perform the desired operation may be much
simpler to write than the equivalent CPU code; GPUs are intended
for this particular use case, and their interfaces reflect this.

One compute pipeline wraps a single compute shader, which
contains the actual code intended to run on the GPU. Compute
shaders have a different execution context from graphics shaders:
they are given workloads from groups of work items called
_workgroups_, each of which represents a single shader invocation
and which may be run in parallel. A compute shader runs in the
context of a _global workgroup_, which can be divided into a
configurable number of _local workgroups_. Shader invocations
within a local workgroup can communicate, sharing data and
synchronizing execution via barriers and the like.

##### Initialization

Compute pipelines are created with
[`vkCreateComputePipelines()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateComputePipelines.html).
This takes an array of pipeline handles and their respective
[`VkComputePipelineCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkComputePipelineCreateInfo.html)s,
in addition to the typical pipeline initialization parameters.

In the creation of a single compute pipeline, the
`VkPipelineShaderStageCreateInfo` parameter must be set to
`VK_SHADER_STAGE_COMPUTE_BIT`. Also, `VkPipelineCreateFlagBits`
includes a compute-pipeline-specific flag
`VK_PIPELINE_CREATE_DISPATCH_BASE`, which allows the pipeline to
be used with
[`vkCmdDispatchBase()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDispatchBase.html)
(see "Dispatch" under "Command buffers"). Otherwise there is
not much to distinguish this process from the creation of other
pipelines.

#### Graphics pipeline

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

#### Ray tracing pipeline

Ray tracing pipelines are designed for simulating the behavior of
light at a high level of detail by tracing the paths of "beams"
of light as they travel through a scene's geometry. They are
created via
[`vkCreateRayTracingPipelinesKHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateRayTracingPipelinesKHR.html).
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

## Shaders: Vulkan and GLSL

We've mentioned shaders here and there, but what actually _is_ a
shader? Speaking in general, a shader is a computer program
written in a shading language, which is a programming language
used to write shaders. Tautological? You betcha. It's hard to
give a rigorous general definition of the term "shader" these
days because although shaders usually run on GPUs, they don't
have to, and although they're often used in the production of
visual imagery, they aren't always. One thing that does stand out
about them compared to other kinds of programs is that they're
mainly intended to be run with hundreds or thousands of
invocations operating in parallel, and synchronization between
these invocations is generally the programmer's responsibility.

Of course, Vulkan is more specific about what a shader is. The
spec describes shaders as "[specifications of] programmable
operations that execute for each vertex, control point,
tessellated vertex, primitive, fragment, or workgroup in the
corresponding stage(s) of the graphics and compute pipelines"
(see [9.
"Shaders"](https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/vkspec.html#shaders)).
So, a vertex shader in Vulkan would be run for every vertex
submitted to a graphics pipeline (see "Drawing" under "Command
Buffers").

Vulkan primarily supports shaders written in a language called
[SPIR-V](https://www.khronos.org/registry/spir-v/specs/unified1/SPIRV.html),
which is in a binary format and not meant to be written directly
by humans. One of the reasons for this is so people can write
their shaders in various higher-level languages that compile to
SPIR-V. We're going to focus on one of these languages: the
[OpenGL Shading
Language](https://www.khronos.org/opengl/wiki/OpenGL_Shading_Language),
or GLSL, and in particular its
[Vulkan-flavored](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.pdf)
variant.

Why GLSL? For one, it's specified by an open standard maintained
by a non-profit. Anyone is free to make suggestions, point out
problems, submit revisions, etc. to the spec and the maintainers
will listen. Development of both the spec and the associated
language tooling happens out in the open, and the tools are all
free software. What's more, the non-profit that maintains GLSL
just so happens to be the same one that maintains Vulkan, so
they've both been designed to play nice together.

What follows is a comprehensive discussion of GLSL from the
perspective of use with Vulkan. It does not assume prior graphics
programming experience, GLSL or otherwise, although it does
assume knowledge of C and C++. It mainly collates information
from the GLSL spec, the Vulkan spec, the GLSL Vulkan extension,
and [the OpenGL
spec](https://www.khronos.org/registry/OpenGL/specs/gl/glspec46.core.pdf)
where applicable.

GLSL is kind of like C with a light dusting of C++ here and there
and stronger built-in support for linear algebra. If you're
comfortable with both C and C++, picking up GLSL will be a breeze
for you. It has some ideas all its own, but like C it's a pretty
small language, so you won't have very far to travel.

As it happens, GLSL has its own definition of "shader". To GLSL,
"shader" is another term for "translation unit". "A computer
program written in a shading language, which is a programming
language used to write shaders"—we're already back where we
started. How's that for circular reasoning?

### Character set

GLSL is encoded in UTF-8. After the preprocessing stage, the only
characters allowed are a–z, A–Z, 0–9, and the following symbols:
`_.+-/*%<>[](){}^|&~=!:;,?`.

The preprocessor uses the number sign (`#`).

Backslashes (`\`) can be used for line continuation; they are
removed before preprocessing ends.

Newlines are indicated by carriage-return, line-feed, or both
together. They are used by the preprocessor and for compiler
diagnostics, but are removed by the time preprocessing ends.

The language is case-sensitive.

### Compilation phases

1. All source strings are concatenated together.
1. Line numbering is recorded based on newline placement.
1. If a backslash occurs right before a newline, both are
   removed. No whitespace is substituted, so you can have a
   single token span multiple lines.
1. All comments are replaced with a single space.
1. Preprocessing is performed.
1. GLSL processing is performed.

### Preprocessor

The preprocessor behaves mostly like the C++ standard
preprocessor.

#### Operators

The preprocessor responds to the `defined` operator and the token
pasting (`##`) operator in the same way as in C++. The same
arithmetic, logical, and bitwise operators are also present, and
behave as they do in C++ as opposed to in GLSL.

Character constants (e.g. a single character enclosed in single
quotes such as `'A'`) are not supported. There is no charizing
operator (`#@`) or stringizing operator (`#`).

There is also not a `sizeof` operator.

#### Predefined macros

`__LINE__` substitutes the current line number. To be specific,
it substitutes an integer one more than the number of
preceeding newlines in the current source string.

`__FILE__` substitutes an integer corresponding to the number of
the source string currently being preprocessed.

`__VERSION__` substitutes an integer corresponding to the version
of GLSL currently in use. The latest version at the time of
writing (which I'm working from here) is indicated by the integer
`460`.

`VULKAN` substitues `100`.

#### Directives

Directives are formed from any number of spaces or tabs, a number
sign (`#`), any number of spaces or tabs, the name of the
directive, and a newline, in that order.

A number sign by itself is ignored.

The directives `#define` and `#undef` are the same as in C++.

The directives `#if`, `#ifdef`, `#ifndef`, `#else`, `#elif`, and
`#endif` are the same as in C++, except that expressions
following `#if` and `#elif` are restricted to those operating on
the output of the `defined` operator and integer literals.

The `#error` directive will print a message into the shader
object's information log at compile time and induce an error
state in the compiler. The message consists of the tokens
following the directive up to the first newline.

Shaders should declare the version of GLSL they are written to
with `#version <number>`, where `<number>` corresponds to the
number substituted for `__VERSION__` (`110` corresponds to 1.10,
`300` corresponds to 3.00, etc.). If a version directive is not
supplied, the compiler will assume you are targeting GLSL 1.10,
which probably isn't what you want. Macro expansion is not done
on `#version` lines.

The `#line` directive can be used to change the current line
number, similarly to in C++. It is used in the form `#line <line>
<source_string_number>`, where `<line>` is a constant integer
expression and `<source_string_number>` is an optional constant
integer expression. If `<source_string_number>` is omitted the
directive is assumed to apply to the current source string.

##### `#pragma`

`#pragma` allows messages to be sent to the compiler. This
directive can only be used outside of function definitions.

`#pragma optimize(on)` and `#pragma optimize(off)` can be used to
turn optimizations on and off. Turning optimizations off can be
helpful for debugging. They are turned on by default.

`#pragma debug(on)` and `#pragma debug(off)` can be used to
enable and disable debug annotations. It is off by default.

##### `#extension`

The `#extension` directive can be used to enable GLSL extensions.
It can be specified as

```glsl
#extension <extension_name> : <behavior>
```

where `<extension_name>` is the name of an extension, or as

```glsl
#extension all : <behavior>
```

`<behavior>` can be one of:

Behavior  | Effect
--------- | ------
`require` | Enable the specified extension or give a compile-time __error__ if it isn't available. Does not accept `all`.
`enable`  | Enable the specified extension or give a compile-time __warning__ if it isn't available. Does not accept `all`.
`warn`    | Enable the specified extension, but warn if it is used, unless the use in question is supported by other `require`d or `enable`d extensions. Also warn if the extension is not available. If `all` is specified, warn on detectable use of any extension.
`disable` | Behave as if the specified extension is not part of the language definition. Warn if the specified extension is not available. If `all` is specified, use only the features of the GLSL core.

The order of `#extension` directives is significant: later
directives will override earlier ones to the extent that they
apply. The compiler initially behaves as if

```glsl
#extension all : disable
```

has been set.

Extensions are allowed to define how widely or narrowly they
apply. If they don't say anything about it, they are considered
to apply to a single shader at a time. The linker can enforce a
wider scope of applicability than this, in which case all the
shaders to which the extension applies will need to contain the
necessary `#extension` directive.

An `#extension` directive must occur before any non-preprocessor
tokens unless the corresponding extension spec says otherwise.

Macro expansion is not done on `#extension` lines.

### Comments

As in C++, comments can be delimted either by `/*` and `*/` or by
`//` and a newline, and in the same manner. Any byte value except
`0` is permitted within a comment.

The line-removal character (`\`) is taken into account before
comment processing, so a comment line ending in `\` will continue
the comment onto the next line.

### Tokens

After preprocessing, valid GLSL consists of tokens. A token is
either a keyword, identifier, integer constant, floating point
constant, operator, or the characters `;`, `{`, or `}`.

### Keywords

The keywords are all predefined and named using the alphanumeric
and underscore characters. We will explore them as we go, but you
can see a comprehensive list at [3.6
"Keywords"](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#keywords)
in the GLSL spec.

### Reserved words

The following keywords are reserved for future use and should not
be used or a compile-time error will result:

```
common partition active
asm
class union enum typedef template this
resource
goto
inline noinline public static extern external interface
long short half fixed unsigned superp
input output
hvec2 hvec3 hvec4 fvec2 fvec3 fvec4
filter
sizeof cast
namespace using
sampler3DRect
```

Also, all identifiers containing two consecutive underscores
(`__`) are reserved for use by underlying software layers.
Although an error will not occur if you define such an
identifier, it may result in unpredictable behavior, so you
shouldn't do so (unless you like to live dangerously).

### Literals

The keywords `true` and `false` are used as Boolean literals.

Integer literals are mostly the same as in C. They can be
expressed in decimal, octal, or hexadecimal, and as signed or
unsigned, in the same manner as in C. The main difference is that
GLSL integer literals do not support the `l`/`L` and `ll`/`LL`
suffixes (we'll discuss their bit width later). Similarly to C,
an integer literal with no suffix is taken to be signed.

Floating point literals are also mostly the same as in C. The
main differences are that the `l`/`L` suffixes are instead
`lf`/`LF` in GLSL, and that floating point literals specify a
single-precision value by default instead of a double.

There are no character or string literals.

### Identifiers

Identifiers are used to name variables, functions, and
structures, and as field selectors for components of vectors and
matricies. They are formed from the alphanumeric and underscore
characters, except that they cannot start with a digit.

In general, identifiers starting with "`gl_`" are reserved, and
you should not declare identifiers in this format. There are
certain situations where identifiers can be redeclared, though,
and in these cases it is permitted to redefine predeclared
"`gl_`" identifiers.

Identifiers can be up to 1024 characters long. Some
implementations may allow them to be longer, but they are
permitted to generate an error if this limit is crossed.

### Expressions

An expression evaluates to a value. Possible expressions are:

* a literal,
* a variable identifier,
* a Boolean expression,
* a ternary selection expression,
* a bit shift or arithmetic operation,
* an increment/decrement expression,
* a function call,
* the use of a constructor,
* a field selection or array indexing operation,
* various nested combinations of the above, or,
* a series of expressions separated by commas.

All expressions have a type, which is equal to the type of the
value they evaluate to. This can be `void`.

### Statements

A statement can be:

* a semicolon,
* an expression followed by a semicolon,
* a declaration,
* a control flow construction, or
* a series of zero or more statements enclosed in braces (`{}`);
  this is a _compound statement_.

### Shaders

In the context of GLSL, a shader is a single translation unit,
generally the contents of a source file. A valid shader contains
declarations, function definitions, and semicolons, although
nothing at all is technically valid.

After compilation, shaders can be linked together into a _shader
executable_. One shader in the set must define a function `void
main()`, which is used as the entry point for the executable.
This function should take no parameters (i.e. its prototype could
also be written `void main(void)`).

### Types

Okay! Now we're getting somewhere. GLSL has a significantly
larger selection of built-in types than C, mainly to support
linear algebra and texture manipulation. There is also support
for user-defined `struct` types akin to those in C.

GLSL is statically typed, and as in C, variable and function
declarations must come with type declarations.

GLSL is type-safe, although there are some implicit conversions
between types.

#### Basic types

##### `void`

This can only be used for functions that do not return a value
and in empty parameter lists.

##### `bool`

A Boolean type, having either the value `true` or `false`.

##### `int` and `uint`

32-bit signed and unsigned integers. Signed integers are two's
complement.

Overflow/underflow behavior differs depending on whether or not
it happens as the result of division. If it occurs from addition,
subtraction, or multiplication, the result is the low 32 bits of
the correct result, as computed with enough precision to avoid
overflow/underflow. If it happens from division, the result is
undefined. (All of this behavior is true whether the integer is
signed or unsigned.)

Signed integer declarations can include a precision qualifier.
There are three available, `highp`, `mediump`, and `lowp`. They
come before the type name, as in `lowp int my_int`. You can only
specify them during variable declaration and they cannot be
changed afterwards. `highp` is the default and implies 32 bits of
precision.

`mediump` and `lowp` both have the same effect; they imply
_relaxed precision_. This means that the integer will be treated
as having somewhere between 16 and 32 bits of precision for any
given operation. Afterwards, the result will be sign-extended
back to 32 bits. (See [2.14 "Relaxed
Precision"](https://www.khronos.org/registry/spir-v/specs/1.0/SPIRV.html#_a_id_relaxedprecisionsection_a_relaxed_precision)
in the SPIR-V spec.)

For a given operation, the precision qualifier in effect will be
the highest _specified_ one in use by any of the operands. If
none of the operands have a precision qualifier specified, the
compiler will use that of the next operation that consumes the
result, recursively. If no precision qualifier is found in this
manner, then a precision at least that of the default for the
type is used.

A default precision qualifier for signed integers can be set via
the statement

```glsl
precision <precision_qualifier> int;
```

where `<precision_qualifier>` is one of `lowp`, `mediump`, or
`highp`. This statement has the same scoping rules as variable
declarations, so it can be applied e.g. just for the body of a
single function.

##### `float` and `double`

Single- and double-precision floating point scalars. (Remember
that floating-point literals are single-precision unless
specified otherwise.) These mostly behave according to IEEE 754,
including support for `NaN`s and `Inf`s and signed zeroes, as
well as the encodings used (at least in logical terms). However,
operations over them work a bit differently than in IEEE 754.
(I'd love to link to the IEEE 754-2019 standard here but it's
behind a hefty paywall.)

Single-precision floating point declarations can also include a
precision qualifier like signed integers can, with the same
keywords. `highp` is the default here as well and implies IEEE
754 32-bit precision. `mediump` and `lowp` imply that, quoting
from the [SPIR-V
spec](https://www.khronos.org/registry/spir-v/specs/1.0/SPIRV.html#_a_id_relaxedprecisionsection_a_relaxed_precision):

> * the floating point range may be as small as (-2<sup>14</sup>,
>   2<sup>14</sup>),
> * the floating point magnitude range may be as small as
>   (2<sup>-14</sup>, 2<sup>14</sup>), and
> * the relative floating point precision may be as small as
>   2<sup>-10</sup>.

As such, the relative error for the result of an operation under
these conditions should be taken as in the worst case (i.e. with
the coarsest precision allowed for).

As with signed integers, single-precision floating point values
can be assigned a default precision via

```glsl
precision <precision_qualifier> float;
```

Assuming `highp`, all the basic arithmetic operations other than
division will perform accurate rounding. The margin of error for
division is 2.5 ULP provided that the magnitude of the divisor is
within [2<sup>-126</sup>, 2<sup>126</sup>]. Given an exponent
_x_, the margin of error for exponentiation is (3 + 2 · |_x_|)
ULP, and the margin of error for taking a logarithm is 3 ULP if
_x_ is outside [0.5, 2.0] or corresponding to absolute error <
2<sup>-21</sup> when _x_ is within that range. Taking the square
root or its inverse has a margin of error of 2 ULP. Conversions
between types are accurately rounded.

Double-precision operations have margins of error at least as
small as their single-precision equivalents.

##### Vectors

GLSL provides 2-, 3-, and 4-component vector types for single-
and double-precision floats, signed and unsigned integers, and
Booleans. They are specified with an optional type prefix, the
string `vec`, and the number of components, in that order. Here
are the prefixes:

Prefix | Meaning
------ | -------
none   | `float`
`d`    | `double`
`i`    | `int`
`u`    | `uint`
`b`    | `bool`

So, a `vec3` is a 3-component vector of single-precision floats,
a `bvec2` is a 2-component vector of Booleans, etc.

##### Matrices

There are built-in matrix types as well, but only for floating
point numbers. They are specified with an optional `d`, the
string `mat`, a digit from 2–4, and an optional `x` followed by
another digit from 2–4. Matrix types specified without `d` hold
single-precision floats, whereas those specified with it hold
double-precision floats. The first digit specifies the number of
columns, and the second digit specifies the number of rows. If
the second digit is omitted, the matrix is square.

For example, `mat3` is a 3x3 matrix of `float`s, whereas
`dmat2x4` is a 2-column, 4-row matrix of `double`s.

#### Opaque types

These are built-in types that behave similarly to opaque handles
in C. They are only intended to be handled through built-in
functions, and do not support direct access to their underlying
value.

##### Texture-combined samplers

These are handles for accessing textures. They are specified with
an optional type prefix, the string `sampler`, and one of a set
of possible strings, in that order. The prefixes are `i` for
signed integer and `u` for unsigned integer; without them,
single-precision float is assumed. The set of possible strings
following `sampler` is:

String        | Meaning
------        | -------
`1`–`3D`      | 1–3D (i.e. `sampler2D` is for a 2D `float` texture)
`1`–`2DArray` | 1–2D array
`2DMS`        | 2D multisample
`2DMSArray`   | 2D multisample array
`2DRect`      | rectangle
`Cube`        | cube-mapped
`CubeArray`   | cubemap array
`Buffer`      | buffer

So, `usamplerCubeArray` is a sampler for an integer cubemap array
texture, `isampler1DArray` is a sampler for a signed integer 1D
array texture, `sampler2DMS` is a sampler for a single-precision
floating point 2D multisample texture, etc.

##### Images

These are handles for accessing images, i.e. all or a part of a
single level of a texture. They are specified just like
texture-combined samplers but with the string `image` substituted
for `sampler`. For example, `uimage2D` is for an unsigned
integer 2D image.

##### Textures

Texture types are handles to textures themselves. They are
specified like texture-combined samplers but with `texture`
substituted for `sampler`.

##### `sampler` and `samplerShadow`

These can be used to create a texture-combined sampler from a
texture type. For example, `sampler2D(texture2D, sampler)` is a
constructor that creates a `sampler2D` from the corresponding
`texture2D`. We'll discuss this in more detail shortly when we
get into constructors.

##### Shadow samplers

There are shadow forms of some of the floating-point `sampler` types for
performing depth texture comparison. These are named by appending
`Shadow` to the type name. The applicable types are:

* `1`–`2D`,
* `1`–`2DArray`,
* `2DRect`,
* `Cube`,
* and `CubeArray`.

So, `sampler2DArrayShadow` is a shadow sampler for a 2D array
texture, for instance. These variants do not exist for the
integral `sampler` types.

We'll get into depth comparisons later on.

##### Subpass inputs

These are handles for accessing subpass inputs within fragment
shaders. Their names all contain the string `subpassInput`. Like
sampler types, they can have a `u` or `i` prefix indicating
integral type, and otherwise are taken as single-precision
floating point. They can also have the suffix `MS`, indicating a
multi-sampled subpass input. So, `subpassInput` is a
single-precision floating point subpass input, `isubpassInputMS`
is a multi-sampled signed integer subpass input, etc.

More on fragment shaders and subpass inputs later.

#### `struct`

User-defined types can be created through use of the `struct`
keyword. The syntax and semantics are similar to C, but not
identical. Here is a basic example:

```glsl
struct shape {
    vec4 position;
    vec4 color;
};
```

This defines a type called `shape` with members `position` and
`color`. Member declarators can have precision qualifiers, but no
other kinds of qualifiers. A struct must be declared with at
least one member.

Anonymous and nested struct definitions are not supported,
although a struct is free to have a member of another struct type.

Structs inherit all the restrictions on the use of any type or
qualifier they contain.

#### Arrays

GLSL supports C-esque arrays, with similar declaration syntax—
the type name, an optional space and identifier, `[`, an optional
size, and `]`, in that order. If the size is specified, it must
be a constant integral expression (not necessarily a literal)
greater than zero. If the space and identifier are included, a
variable declaration is formed (`vec4 colors[];`); without them,
a type specifier is formed (`float[5]`).

Any type in the language can be used for the contents of an
array. This includes array types, so arrays-of-arrays and so on
can be declared (e.g. `float[5][3]`, meaning a 5-element array of
`float[3]`). However, arrays are homogeneous; all elements must
be the same type.

The maximum size of an array is implementation-defined; it is not
formally restricted in any general sense (see "Array" under
[2.2.2
"Types"](https://www.khronos.org/registry/spir-v/specs/unified1/SPIRV.html#_types)
in the SPIR-V spec).

### Implicit conversions between types

GLSL has a variety of implicit conversions that will be performed
in some cases, such as during assignment. You can view the complete
list at [4.1.10 "Implicit
Conversions"](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#basic-types)
in the GLSL spec.

If an operation occurs with a floating point operand and an
integral operand, the integral operand is implicitly converted to
match the type of the floating point operand. If an operation
occurs with `int` and `uint` operands, the `int` is implicitly
converted to a `uint`. If an operation occurs with `float` and
`double` operands, the `float` is implicitly converted to a
`double`.

All the implicit conversions defined are for basic types. There
aren't any for array or struct types.

When implicit conversion does occur, it follows the same rules as
with explicit conversion via constructors.

### Constructors

Constructors provide for explicit, well-behaved type conversion
and give a way to build up anonymous values on the fly,
overlapping with some uses of both initializer lists and casts in
C++. The syntax for using a constructor is a type specifier, `(`,
one or more assignment expressions, and `)`, e.g. `int(1.0)` or
`bool[4](true, false, true, false)`.

#### Scalars

The basic scalar types (`int`, `uint`, `float`, `double`, and
`bool`) all support conversions between each other via
constructors.

When constructing an integer from a floating point value, the
fractional part is dropped. Constructing a `uint` from a negative
floating point value is undefined.

Constructing a floating point value from an integer when the
integer value has more bits of precision than allowed for by the
mantissa of the floating point type in question will lose
precision in the conversion, as is typical.

Converting between `int` and `uint` will preserve the bit
pattern, so the logical value will change accordingly.

When constructing a bool from a value of any of the other scalar
types, `0` and `0.0` produce `false`, and any other value
produces `true`. Going the other direction, `false` produces `0`
or `0.0`, and `true` produces `1` or `1.0`.

Constructing a scalar from a vector or array will work with the
first element of the argument.

```glsl
float(bvec2(true, false)) == 1.0;
```

#### Vectors and matrices

Vectors and matrices can be constructed from a set of scalars,
vectors, or matrices.

When constructing a vector from a single scalar value, the value
will be used to initialize every component of the vector.

When constructing a matrix from a single scalar value, the value
will be used to initialize every component on the matrix's
diagonal, with the other components set to `0.0`.

When constructing a vector from a list of scalars and/or vectors
and/or matrices (they can be mixed), each component of each
argument will be consumed from left-to-right (matrix components
in column-major order) until the new vector is filled. This also
works for constructing matrices, except that using matrices in
the argument list is not allowed, and the number of components in
the arguments must exactly match the number of components in the
new matrix.

When constructing a matrix from another matrix, each component in
the argument that corresponds by row and column to a component in
the new matrix will be used to initialize that component. Any
remaining uninitialized components will be initialized from the
identity matrix for the type of the new matrix.

The scalar conversion rules above will be used to construct the
individual components of the new vector or matrix if the types of
the components in the arguments don't match theirs.

#### Structures

After a structure type has been named and defined, values of it
can be made via a constructor. The rules for the arguments
correspond to those for structure initializer lists.

#### Arrays

An array type specifier (such as `float[5]`) can be used as the
name of a constructor to construct arrays of that type. The rules
for the arguments correspond to those for array initializer
lists.

#### Texture-combined samplers

Texture-combined samplers (e.g. `sampler2D`) can be constructed
from a texture (e.g. `texture2D`) and a `sampler` or
`samplerShadow`, in that order. However, there are significant
limitations on their use: the new sampler can _only_ be used as
an argument to a function, meaning it cannot be assigned to a
variable or used in any control flow constructs. The
dimensionality of the texture type of the first argument must
correspond to that of the new sampler. Shadow mismatches are
allowed between the second argument and the new constructor (i.e.
`samplerCubeShadow(textureCube, sampler)` is a valid "constructor
prototype").

### Variables

Variables in GLSL are similar to those in C. They're statically
typed, named via an identifier, and can hold a value. As in C,
variable declaration and initialization are separate
concepts.

#### Declaration

Declaring a variable brings it into scope. With the exception of
implicitly-sized arrays, a variable cannot be redeclared once it
is in scope.

##### Basic and opaque types

Variables of one of the basic or opaque types are simply declared
by writing the type name, an identifier, optionally one or more
other identifiers separated by commas, and a semicolon.
For example:

```glsl
uint        count;
vec4        color, position;
mat4x4      rotation;
samplerCube skybox;
```

Personally, I don't like declaring more than one variable per
line, because I think it's too easy to make mistakes around and
makes the code harder to read. But that's just my opinion.

##### Arrays

Array variables are generally declared as described in "Arrays"
earlier (`vec4 positions[10];` and so on). You may recall that
the size is optional.

Implicitly-sized array variables can be redeclared after their
initial declaration. If an array is declared unsized, it must be
redeclared with an explicit size before the array can be indexed
with anything aside from a constant integral expression (although
indexing an unsized array _with_ a constant integral expression
is permitted). The compiler will throw an error if you try to
redeclare an array with a size equal to or smaller than the
largest number used to index into it thus far in the shader. Once
redeclared with an explicit size, the array variable cannot be
redeclared.

The compiler will throw an error if you try to index into an
explicitly-sized array outside its bounds.

##### Structs

After a struct has been defined, struct variables can be declared
in the same manner as with basic types (`my_struct
my_struct_inst;`). However, it is also possible to define a
struct and declare one or more variables of it in one go, like so:

```glsl
struct my_struct {
    vec4 ns;
    bool flag;
} my_struct_inst, my_other_struct_inst;
```

This defines a struct `my_struct` _and_ declares `my_struct`
variables `my_struct_inst` and `my_other_struct_inst`. All will
be in scope from this point, so you will be able to declare other
`my_struct` variables after this. That said, I think this syntax
is a bit confusing if you're going to use the struct type in
other declarations afterwards.

If you want to apply qualifiers (decribed later) to variables
declared this way, they go before `struct`:

```glsl
const struct ext_flags {
    bool hairy;
    bool shiny;
    bool soft;
} dog { true, true, true };
```

This declares a `const` variable called `dog` of type
`ext_flags`, in addition to defining the struct type `ext_flags`.

#### Assignment

Once a variable has been declared, a value can be assigned to it.
Reading from a variable before it has been initialized or
assigned to will return an undefined value.

To assign a value to a variable, write the variable's name, `=`
(the assignment operator), and an assignment expression, followed
by a semicolon. An assignment expression can be any expression
except a comma-separated list of expressions.

Here are some examples (presuming these variables have already
been declared):

```glsl
n      = 6;
n_copy = n;
never  = 1 == 0;
always = true ? true : false;
max    = (1u + 1u) << 31;
after  = ++before;
one    = cos(0);
green  = vec4(0.0, 1.0, 0.0, 1.0);
red    = green.grba;
```

If a variable has not been declared as `const`, it can be
repeatedly re-assigned to. In this case, in addition to the
regular assignment operator `=`, you can also use the arithmetic
assignment operators, which correspond to their non-assignment
operators in a manner akin to C's (`+=`, `-=`, `*=`, `/=`, `%=`,
`<<=`, `>>=`, `&=`, `|=`, and `^=`). There are also pre- and
post-decrement operators `++` and `--`, which are also akin to
those in C, except that they can be used with floating-point
variables (adding or subtracting `1.0`).

You can also assign to array elements and vector and matrix
fields; this is described below.

As GLSL is statically typed, the value the assignment expression
evaluates to must match the type of the variable being assigned
to, unless there is an applicable implicit conversion (see
"Implicit conversions between types" above).

#### Initialization

During variable declaration, you can supply an initial value for
a variable by adding an `=` after the identifier and supplying an
assignment expression (described above) before the semicolon.

```glsl
int    n      = 6;
int    n_copy = n;
bool   never  = 1 == 0;
bool   always = true ? true : false;
uint   max    = (1u + 1u) << 31;
double after  = ++before;
float  one    = cos(0);
vec4   green  = vec4(0.0, 1.0, 0.0, 1.0);
vec4   red    = green.grba;
```

Variables are mutable by default. However, they can be made
immutable after initialization by adding the storage qualifier
`const` before the type name:

```glsl
const int n = 0;
n = 1; // compiler error
```

Vectors, matrices, arrays, and structs can also be initialized
using an _initializer list_. As in C++, the syntax is an open
brace (`{`), assignment expressions or initializer lists
separated by commas, and a close brace (`}`).

```glsl
ivec4 ns = { 0, 1, 2, 3 };

float[][] nested = {
    { 1.6, 2.5, 3.4 },
    { 4.3, 5.2, 6.1 }
};

mat3x2 matching = {
    { 1.6, 2.5, 3.4 },
    { 4.3, 5.2, 6.1 }
}

struct mat {
    vec4  color;
    float metal;
    float rough;
} golden {
    { 1.0, 0.766, 0.336, 1.0 },
    0.5,
    1.0
};

```

When assigning the elements of the initializer list to the
elements or fields they apply to, the rules described above in
"Assignment" apply.

In GLSL, initializer lists can _only_ be used in formal
initialization (i.e. as part of a declaration statement). This of
course stands in contrast to C++, where an initializer list can
be used to initialize an unnamed temporary for a function argument
or the like. Constructors in GLSL help to make up for this
limitation (see "Constructors").

It is worth noting that GLSL has a sequence operator (`,`) with
similar behavior to C's. As a result, initializing multiple
variables on one line has the same (rather beguiling) behavior:

```glsl
int a, b = 4;
int c = a; // c's value is undefined
```

I advise sticking to one initialization per line to avoid this
sort of confusion.

#### Scope

A variable's scope depends on where it is declared. If it is
declared at the top level (i.e. outside of any function
definition), it has global scope, and is available anywhere in
the shader. It is also available immediately after being declared
and no earlier, such that silly constructions like

```glsl
int x = 1, y = x;
int two = x + y;
```

and the like are permissible.

If a variable is declared within a compound statement, it is only
available within that compound statement. Its scope can also be
restricted if it is declared within a function definition, a loop
body, a conditional expression, etc.; we will describe these
rules as we discuss the applicable concepts.

### Operators

The operators are largely the same as in C, with the exception of
the address-of, dereference, and typecast operators, which
naturally are missing. We'll explore them here, but see [5.1
"Operators"](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#operators)
in the GLSL spec for the complete list, including precedence and
associativity information.

#### `()` (expression grouping)

Expressions can be grouped with parentheses as in C.
Parenthesized expressions will be evaluated before expressions
across parentheses.

#### `()` (function call, constructor)

Covered in their own sections.

#### `+`, `-`, `*`, `/`, `%`

These are the usual arithmetic operators. With scalars, these
work as you would expect based on C. However, they are also
defined over vectors and matrices. In most cases, arithmetic
operations involving vectors or matrices happens componentwise.
This includes operations between a scalar and a vector or matrix.
The exception is multiplication in which both the operands are a
vector or matrix, in which case the operation proceeds as in
linear algebra.

#### `<<`, `>>`, `&`, `^`, `|`, `~`

These are the usual bitwise operators. For integers, these work
mostly like in C, except that they work with both signed and
unsigned operands. A bitshifted signed integer will be
sign-extended, and performing bitwise Boolean algebra on signed
integers will taken into account the sign bit(s) (although you
should note that such an operation between a signed and unsigned
integer will cause the signed integer to be converted to an
unsigned integer beforehand). They also work componentwise with
integer vectors.

#### `=`, `+=`, `++`, etc.

The assignment operator, arithmetic and bitwise assignment
operators, and increment/decrement operators are discussed under
"Assignment".

#### `&&`, `||`, `^^`, `!`

The logical binary operators (`&&`, `||`, `^^`) operate only on
Booleans. This is also true of the logical NOT (`!`). There is a
built-in function `not()` that accepts a vector, however.

#### `==`, `!=`

The equality operators (which naturally return a Boolean) will
only work with basic types. Both operands must be the same type
and size; if operating on arrays, both arrays must be explicitly
sized. For composite types, comparison is done componentwise.

#### `<`, `>`, `<=`, `>=`

The relational operators only operate on scalar expressions.
Their types must match or support an implicit conversion. The
result is a Boolean. For componentwise relational comparison of
vectors, there are built-in functions `lessThan()`,
`greaterThan()`, `lessThanEqual()`, and `greaterThanEqual()`.

#### `?:`

This is the ternary selection operator, akin to C's. It operates
on three expressions, like so:

```glsl
bool_exp ? exp1 : exp2
```

`bool_exp` must be a Boolean expression. If it is `true`, the
expression evaluates to `exp1`; if `false`, `exp2`. `exp1` and
`exp2` can evaluate to any basic type including `void`; however,
their types must match, or at least support an implicit
conversion.

#### `[]`

This is the indexing operator, used to index into arrays with the
same syntax as in C. Indices start at zero and go up to one less
than the array's size, as you would expect. Both signed and
unsigned integer expressions can be used to access elements, but
subscripting an array with an index less than `0` is undefined,
so you may want to stick to unsigned integers for this purpose.
This operator can also be used to access the components of
matrices and vectors, with the same syntax.

#### `.` (component/field selector)

The components of vectors and scalars and the fields of
structures can be accesed with this operator. Accessing struct
fields with it is the same as in C. In the case of vectors, each
of the components has three predefined names, as follows:

* `{ x, y, z, w }`, nice for points and normals;
* `{ r, g, b, a }`, nice for colors;
* `{ s, t, p, q }`, nice for textures.

You can use whichever you like, but you can only pick from one
set at a time. For example:

```glsl
vec4 v4;
v4.rgba; // this is fine
v4.xyzw; // so is this
v4.sgzq; // this is not
```

For scalars and vectors of length less than four, their
components are named in the same manner, as far as they can be.
E.g.

```glsl
float n;
n.s;

vec3 v3;
v3.xyz;
```

You can select a shorter vector from a longer one:

```glsl
vec4 v4;
vec3 v3 = v4.stp;
```

Swizzling works as well:

```glsl
vec4 v4;
vec4 swiz = v4.wwxy;
```

You can assign to multiple components of a vector at once using
the same syntax:

```glsl
vec4 v4;
vec2 v2;
v4.zw = v2;
```

#### `.` (method call)

There is a method call operator `.` with only one use,
`length()`. This can be called on both arrays and vectors. It
returns an `int` equal to the number of elements in the array or
vector (I have no idea why it does not return a `uint`). Calling
`length()` on an array that has not been explicitly sized or
attained an implicit size will provoke a compiler error.

```glsl
int[5] ns;
int ns_len = ns.length();
bool is_true = ns_len == 5;

vec4 v;
bool also_true = v.length() == 4;

int[] unsized;
int unsized_len = unsized.length(); // error
```

#### `,`

This is the sequence operator, like C's. It operates on
basic-typed expressions (including `void`). If there is a
comma-separated list of such expressions, they are evaluated from
left-to-right and the value of the rightmost expression is
returned.

### Control flow

#### Conditional

##### `if`-`else`

GLSL supports a simple `if`-`else` construction, like C's:

```glsl
if (true) {
    // always reached
}

if (false) {
    // never reached
} else if (true) {
    // always reached
} else {
    // never reached
}
```

Any Boolean expression can be used within the parentheses. The
braces are optional (they're just the normal compound statement
braces). I always use them for the sake of readability, though.

Each branch of a conditional construction has its own scope.

##### `switch`

GLSL also supports a `switch` statement akin to C's, with
essentially identical syntax and semantics (fall-through,
`break`, `default`, etc.). Here's an example just for kicks:

```glsl
switch(2) {
case 1:
    // never reached
case 2:
    // always reached
case 3:
    // always reached
    break;
case 4:
    // never reached
default:
    // never reached
}
```

In practice, this would not actually compile as written, as empty
`case` branches are not permitted. The expression in parentheses
and those for each `case` must evaluate to scalar integers, and
the `case` expressions must be constant.

A `switch` statement forms a new scope. The `case` branches do
not establish a new scope on their own, but of course they allow
for compound statements if this is desired.

#### Looping

Just like in C, including the scoping rules.

##### `for`

```glsl
vec4 v4;

for (uint i = 0; i < v4.length(); ++i) {
    v4[i] = i;
}

bool is_true = v4 == vec4(0.0, 1.0, 2.0, 3.0);
```

##### `while`

```glsl
while (int i = eventually_five()) {
    if (++i == 6) {
        break;
    }
}

int i = 0; // `while`'s `i` is no longer in scope
do {
    if (++i == 6) {
        break;
    }
} while (i = eventually_five());
```

Note that the conditional expression in the `do`-`while`
statement cannot declare a variable.

#### Jumping

##### `continue`

Used only in loops; skips the remainder of the body of the
innermost loop in which it is found.

##### `break`

Used in loops and `switch` statements; immediately leaves the the
innermost loop or `switch` statement in which it is found.

##### `discard`

This is used in fragment shaders to abandon the current fragment.
We'll discuss it later on.

##### `return`

This is used to leave functions; we'll discuss it shortly.

### Functions

At last!! We're really getting somewhere now.

A function is essentially a list of statements that, when called,
are evaluated as an expression. They can accept parameters that
are treated like variables in the statement list and for which
concrete values are substituted in at call time. In other words,
they're quite similar to functions in C (although there are no
function pointers, sadly…). They have a variety of tricks up
their sleeve that C functions do not, however.

#### Declaration and definition

Like variables (and like C functions), functions can be declared
and defined separately or together. Both must be done at the top
level (i.e. in the global scope for the shader). A function
declaration consists of its prototype followed by a semicolon. A
function prototype consists of a type specifier, an identifier,
`(`, zero or more parameter declarations separated by commas, and
`)`, in that order. A parameter declaration consists of zero or
more qualifiers, a type name, an optional identifier, and
optional array brackets and sizes if applicable. A function
definition consists of a function prototype, `{`, a list of
statements, and `}`. That might seem like a lot to keep track of,
but it's mostly the same as the C syntax.

```glsl
uint meow(const int, bool);

uint meow(const uint count, bool cow)
{
    uint meows = 0;
    for (; meows < count; ++meows) {
        emit_meow();
    }

    if (cow) {
        return 0;
    } else {
        return meows;
    }
}
```

As you can see, the function body can include the keyword
`return`, which can be followed by a value. When the function is
called, `return` causes the function to exit immediately and for
the function call expression to evaluate to the returned value
(if any). The value `return`ed should either match the type the
function was declared with or have an implicit conversion to it.
As in C, functions can be of `void` type, in which case they
don't need to `return` (although they can if they want to exit
early).

You may recall from "Shaders" that one function in a shader
executable must have a function with prototype `void main()`,
which is used as the entry point for the executable. This
function is allowed to use `return`, which will cause an early
exit from the executable if encountered before the end of the
function.

As you may have noticed, arrays are both accepted as parameters
and make for a valid return type. They must be explicitly sized
in both cases, though. Structures are also allowed as both
parameters and as a return type.

Only a precision qualifier (like `lowp`) can be applied to the
return type of a function. Function parameters can be specified
with parameter, precision, and memory qualifiers.

In place of pointers or references, the qualifiers `in`, `out`,
and `inout` can be applied to parameters. Specifying `in` is the
same as not specifying any of the three; it means the argument
will be copied in but not out, i.e. pass-by-value. `inout` is
similar to pass-by-reference; a local copy of the argument will
be made for the body of the function and any changes to it will
be written to the original variable when the function exits.
`out` means that the passed-in value of the parameter is ignored,
but its value at return time will be copied back into the
variable in question; this is preferable to `inout` in efficiency
terms if the initial value isn't needed.

```glsl
void fill_arr(out float[10] arr)
{
    for (uint i = 0; i < arr.length(); ++i) {
        arr[i] = i;
    }
}
```

Overloads are supported. As in C++, the return type and function
name must be the same, and the parameters must differ. The rules
for finding a best match given a set of parameters are also
similar to C++'s (see [6.1 "Function
Definitions"](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#function-definitions)
in the GLSL spec if you want the exhaustive treatment).

Functions can be redeclared and redefined. This includes built-in
functions. If a shader redeclares a built-in function, the linker
will only attempt to resolve calls to it within that shader and
the set of shaders linked to it (i.e. it will not resolve the
call to the built-in definition).

Recursion is not supported in any capacity, sadly.

#### Calling

The syntax for a function call is the function's name, `(`, zero
or more assignment expressions (see "Assignment"), optionally
`void` in place of any assignment expressions, and `)`, in that
order.

```glsl
void fill_arr(out float[10]);

float[] arr;

fill_arr(arr);
```

Naturally, the assignment expressions will be used to assign a
value to each corresponding parameter in the body of the
function. As described above, a function call is an expression
which evaluates to the value returned after the call is executed.

### Kinds of shader

At this point, we've described most of the syntax and semantics
of GLSL as it is used with Vulkan. From here, we can start to
explore the interface between GLSL shaders and Vulkan, and thus
between shaders and other shaders as well. We still have some
parts of GLSL to cover, but they'll be easier to understand in
that context.

Vulkan supports a variety of different kinds of shader, which do
different sorts of work. Each kind is associated with one of the
types of pipeline. We're going to describe them at a high level
here, just enough that we can continue our discussion.

#### Graphics

These are the different kinds of shaders you can run in the
context of a graphics pipeline.

##### Vertex

Work is provoked in a graphics pipeline by submitting a set of
vertices to it with a draw command, as you might recall. The
vertex shading stage is the first in the pipeline; each vertex
submitted generates an invocation of the vertex shader. These
each receive the data for a vertex and any information associated
with it, perform whatever operations on this data they need to,
and then send the results down to the next stage. A graphics
pipeline must have a vertex shader.

When rendering a 3D scene, one of the most common things for a
vertex shader to do is project the scene onto the 2D space of the
screen so it can be rendered from the desired vantage point.

##### Tessellation control

Tessellation control shaders are optional; fixed-function
primitive assembly is performed without them.

Vertices leaving the vertex shading stage are organized into sets
of vertices called _patches_ (the number of points in a patch is
configurable via
[`VkPipelineTesselationStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineTessellationStateCreateInfo.html)
during graphics pipeline creation). These become _input patches_
into the tessellation section of the graphics pipeline if
tessellation is enabled for that pipeline. The tessellation
control shading stage receives these input patches and produces
output patches for the tessellation evaluation stage. A single
tessellation control shader invocation runs for each control
point of an output patch; if output patches were set in the
shader to have four control points, each input patch would
produce four tessellation control shader invocations, each
operating on that input patch.

A tessellation control shader can specify how many control points
go into an output patch, and thus can add extra vertices that
were not present during vertex shading or discard some vertices.
This can be used to add interpolating points between the vertices
coming into the graphics pipeline, or even perform complex
modifications to the vertex data. It can also specify the amount
of tessellation performed at the edge and in the interior of
the primitives before the tessellation evaluation stage.

##### Tessellation evaluation

For a tessellation control shader to be used, a tessellation
evaluation shader must be supplied as well. Between the
tessellation control and tessellation evaluation stages, a
fixed-function tessellator assembles abstract primitives from the
patches. Afterwards, the tessellation evaluation stage is
responsible for actually specifying the position and other data
associated with the vertices in the abstract primitive. An
invocation runs for every vertex generated by the tessellator.

Tessellation evaluation shaders are able to control some aspects
of how the tessellation primitive generator operates, such as the
kind of primitives that are assembled and the spacing of the
vertices.

If you're using tessellation shaders, you can perform a lot of
the work traditionally done in the vertex shader here instead,
using the vertex shader to prepare the incoming vertex data
appropriately for your tessellation shaders.

##### Geometry

Geometry shaders run per primitive, either from automatic
primitive assembly as dictacted during graphics pipeline creation
or as produced by the tessellation stages if tessellation is
enabled. Like tessellation shaders, they are optional; the
assembled primitives will just be passed along otherwise.

If tessellation is not enabled, they are able to control the type
of primitive they receive as input, similarly to the tessellation
evaluation shader. They are also able to control the number of
times they run for each primitive.

They can also take over the traditional work of the vertex
shader, as the tessellation evaluation shader can. Since they
operate on whole primitives, though, they have a rather different
perspective on the geometry than the tessellation shaders do.

##### Fragment

After vertex processing occurs (which includes the tesselation
and geometry stages if used), some vertex post-processing such as
primitive clipping occurs. After that, the rasterization stage
produces fragments from the vertex data, which are data
associated with rectangular framebuffer regions. A fragment
shader invocation receives one of these fragments as input and
outputs values that can be applied to framebuffer or texture
memory, like color information. In plainer language, the fragment
shading stage is where drawing actually happens. Fragment
shaders are required in a graphics pipeline.

#### Compute

The compute pipeline runs only one type of shader, the compute
shader. These provide a mechanism for doing "generic" computation
in Vulkan, although they can be very useful for certain kinds of
graphics operations because of their low overhead.

#### Task, mesh, ray tracing, intersection, any-hit, miss, and callable

These shaders are not part of core GLSL or Vulkan, but rather are
enabled by various extensions. Task and mesh shaders are part of
mesh shading, which my GPU doesn't support at all, and the rest
are part of ray tracing, which my GPU only barely supports and
can't really do in real time. Since this is focused on what a
game engine needs and thus has to stick to real time stuff, I'm
not going to cover any of these.

### Compilation

You can actually send your GLSL shaders right into a Vulkan
pipeline and they'll be compiled by the graphics driver on the
fly. That's not the best plan if you're worried about
performance, though. Instead, you can compile your GLSL shaders
into SPIR-V binaries beforehand and use those in Vulkan, which
will make less work for the driver.

The reference compiler for GLSL is
[glslang](https://www.khronos.org/opengles/sdk/tools/Reference-Compiler/),
maintained by The Khronos Group. You can see that page for more
info, but just in brief, you can put your shader code in text
files named according to the following conventions:

* `*.vert` for a vertex shader,
* `*.tesc` for a tessellation control shader,
* `*.tese` for a tessellation evaluation shader,
* `*.geom` for a geometry shader,
* `*.frag` for a fragment shader, and
* `*.comp` for a compute shader,

and then compile them like so:

```
glslangValidator --target-env vulkan1.2 [FILE]
```

This will output a Vulkan-oriented SPIR-V binary under the name
`<stage>.spv`, optimized for performance.

If your shader codebase is getting large, `glslangValidator`
supports the flag `-l` which will allow you to pass multiple
filenames and will link them all into a single module. It also
supports the handy parameter `--variable-name <name>`, which will
create a C header file with a `uint32_t` array called `<name>`
initialized with the SPIR-V binary code.

SPIR-V Tools also has a linker called `spirv-link` that can link
multiple SPIR-V binaries together into one module. If you want to
put a whole pipeline's worth of shaders into one module or that
sort of thing, `glslangValidator` takes the argument
`--source-entrypoint <name>` which allows you to pick an entry
point name other than `main` for the module. Once you've compiled
each of your executables, setting the proper entry point for
each, you can link them together into one module with `spirv-link`
and select the right entry points from it for each pipeline stage
during pipeline creation on the Vulkan side.

### Vulkan shader linkage

There are actually two different kinds of linkage at play when
talking about GLSL and Vulkan. Thus far in our discussion of
GLSL, we've mainly meant the kind of linkage we just discussed
above—linking one or more shaders together into a shader
executable, like what glslang does. However, Vulkan also uses the
term "link" when talking about what happens when multiple shader
executables are linked together in the context of a pipeline.
That's what we're going to focus on for the rest of our
discussion of GLSL. We keep referring to shaders taking in data
from the outside world and passing it on afterwards—now we can
explore how that actually happens.

#### Modules

Once you've got your shaders ready, you can get them into Vulkan
via _shader modules_, represented by `VkShaderModule`. The
function to create a shader module is
[`vkCreateShaderModule()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateShaderModule.html).
This utilizes a
[`VkShaderModuleCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkShaderModuleCreateInfo.html),
which mainly takes a pointer to the code and the size of the code
in bytes. If you are using a validation cache, you can add it to
this struct's `pNext` chain to make use of it with the module in
question (see "Validation cache" below for the specifics).

All the pipeline creation functions take at least one
`VkPipelineShaderStageCreateInfo`. This is where you can put your
`VkShaderModule` in order to join it to the appropriate pipeline
stage. (See "Initialization" under "Pipelines" for more on this.)

To destroy a shader module, use
[`vkDestroyShaderModule()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyShaderModule.html).
It's okay to call this while pipelines created with the module in
question are still in use.

#### Passing data around

Each pipeline establishes certain interfaces between the rest of
Vulkan and the pipeline, by which data can travel in and out.
They also establish ways that shader invocations can pass data
around between each other. The shaders themselves also have ways
of defining interfaces between their interior and the larger
world, as we've mentioned. Finally, pipelines need to be joined
to a command buffer for you to make use of them, possibly within
a render pass, and this process provides various ways of getting
other Vulkan objects into the same context as the pipeline so
that its shaders can ultimately work with them. All of these
domains need to collaborate, so even though we're going to get
back to GLSL from here on out, we'll take frequent trips over to
the Vulkan side to talk about how to set things up appropriately
over there based on what you might be doing in your shaders.

### Qualifiers

Qualifiers are keywords used in declarations before the type name
that have some effect on how the subject of the declaration is or
can be handled. We've already encountered some of them, like
`lowp` and `inout`. However, we've delayed a comprehensive
discussion of them until now because they play a major role
in how your shader interfaces with the outside world. Since we've
laid the groundwork, we can now discuss them.

#### Storage qualifiers

When declaring a variable, a single storage qualifier can be
specified before the type name, which can determine aspects of
the variable's mutability, linkage, and interpolation strategy.
There are also a few auxiliary storage qualifiers that can be
specified along with a storage qualifier.

As we've already discussed, if no qualifier is specified, the
variable is local to the shader and mutable. If `const` is
specified, the variable is local to the shader and immutable
after initialization. The rest of the storage qualifiers are new
to us.

##### Input and output variables

Global variables can be declared with the storage qualifiers `in`
and `out`. `in` indicates that the variable will get its value
from outside, such as from a previous pipeline stage. `out`
establishes an output interface between the current shader and
subsequent pipeline stages.

The compiler will throw an error if you try to write to a
variable declared with `in`. Also, there is no `inout` storage
qualifier for variables, nor is it permitted to qualify a
variable with both `in` and `out`.

You can declare an output variable and not write to it as long as
the subequent stages don't make use of it; similarly, an input
variable that doesn't actually get written to by anything is okay
as long as you don't try to read from it. If you do try to read
from an input variable and a prior stage hasn't declared it, you
will get a link-time error; if a prior stage has declared it but
hasn't written to it, its contents will be undefined.

###### In the vertex shader

Vertex shader inputs are all per-vertex, and the vertex data has
to be passed in from the Vulkan side. We'll talk about this in
more detail when we discuss the qualifier `layout`.

Vertex shader inputs cannot be or contain a value of Boolean,
opaque, or structure type.

Graphics hardware tends to only support a relatively small number
of vertex inputs. You can query the exact number via
`VkPhysicalDeviceLimits`; my graphics card supports 32 of them,
as an example. Scalars and vectors count against this limit
equally, so you may want to pack unrelated scalars into a vector
before sending them into the vertex shader. Matrices count
multiple times, once for each column.

###### In the tessellation control, evaluation, and geometry shaders

Each of these shaders in turn receives per-vertex values written
by the prior stage. Since they all operate on sets of vertices,
each (non-`patch`) input should be an array; each element will
correspond to one of the vertices. The tessellation control
shader must also declare its non-`patch` outputs as arrays.

It is permitted, but not required, to set an explicit size for
these arrays; if explicitly sized, the size must match the size
that would be otherwise used by the implementation. For this
reason, the shaders will be easier to maintain if the
input/output arrays are left implicitly sized.

The geometry shader's inputs will be sized according to the type
of primitive it receives.

The tessellation control shader can use the auxiliary storage
qualifier `patch` on its outputs; the tessellation evaluation
shader should qualify its matching inputs in the same manner.
This indicates that the variable will be set per-patch instead of
per-vertex by the implementation, and thus is not required to be
an array.

A tessellation control shader invocation operates on a single
vertex in a patch. It has a built-in output variable `struct
gl_PerVertex gl_out[]` containing data for every vertex in the
patch. Each invocation must only assign to fields in the
structure at index `gl_InvocationID` in `gl_out[]`, which
corresponds to the data for the current vertex.

Tessellation control shader invocations for the same patch
operate in an undefined order relative to each other unless the
function `barrier()` is used, which can create a synchronization
point between them. The start and end of the shader can also be
seen as synchronization points; you can think of the activity of
the invocations as filling in `gl_out[]` in parallel. This
implies that, sans `barrier()`, elements in `gl_out[]` may be
undefined for a given invocation during execution.

The inputs and outputs of these stages cannot be or contain a
value of Boolean or opaque type.

###### In the fragment shader

Fragment shader inputs and outputs are per-fragment. The inputs
are typically interpolated from the outputs of the previous
stage, and support the interpolation qualifiers `flat`,
`noperspective`, and `smooth`, in addition to the auxiliary
storage qualifiers `centroid` and `sample`. We'll discuss all of
this in more detail in the section "Interpolation qualifiers".
The outputs should not be qualified with any auxiliary storage or
interpolation qualifiers.

Fragment shaders receive their inputs from the last active vertex
processing stage (vertex, tessellation evaluation, or geometry).
Therefore, whichever stage this is should match its outputs with
the inputs of the fragment shader. There is no need for the
previous stages to match the interpolation or auxiliary storage
qualifiers of the fragment shader's inputs, though.

The inputs of a fragment shader cannot be or contain
a value of Boolean or opaque type, and its outputs cannot be or
contain a value of Boolean, double-precision scalar or vector,
opaque, matrix, or structure type.

###### In the compute shader

Compute shaders don't support input or output variables (except
for a few built-in inputs). They have to interface with the
outside world through other means.

##### Uniform variables

Variables declared in a block can take the storage qualifier
`uniform` to indicate that they are initialized from the Vulkan
side. Such variables are read-only and will have the same value
across every invocation interacting with the same primitive.

`uniform` can be used with variables of basic or structure type,
or arrays of these types.

Since uniform variables all exist in a single global namespace at
link time, they need to be declared with the same name, type,
etc. in any shader that makes use of them.

##### Buffer variables

The storage qualifier `buffer` indicates variables that are
accessed through a `VkBuffer` bound to the pipeline the shaders
are attached to. It must be used to qualify a block.

##### Shared variables

Compute shaders can use the storage qualifier `shared` to declare
global variables that have shared storage across all invocations
in the same workgroup.

`shared` variables should not be declared with an initializer; as
such, their contents are undefined at the time of declaration.
Any data written to them after that point will be visible to
the other invocaitons.

Access to these variables is coherent across invocations.
However, it is not inherently synchronous; access to them should
be synchronized with `barrier()` if needed.

There is a limit to how much memory can be allocated for shared
variables on a given device. This is specified in bytes in
`VkPhysicalDeviceLimits` under `maxComputeSharedMemorySize`. On
my run-of-the-mill graphics card, this is ~50kB. For shared
variables declared in a uniform block, you can determine their
layout in memory by the rules in [15.6.4 "Offset and Stride
Assignment"](https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/chap15.html#interfaces-resources-layout)
in the Vulkan spec. The amount of storage consumed by shared
variables not declared in a block is implementation-dependent,
but cannot be more than would be consumed if all the non-block
shared variables were laid out in a block with the smallest
possible valid offset following the [standard buffer
layout](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#interfaces-resources-standard-layout)
rules in "Offset and Stride Assignment".

##### Interface blocks

Global variables can be grouped together into named _interface
blocks_ that can be qualified with `in`, `out`, `buffer`, or
`uniform`, and which also support the auxiliary qualifier `patch`
for `in` and `out` blocks. Input and output blocks define
interfaces between shader stages similarly to input and output
variables. `buffer` and `uniform` blocks represent an interface
to a `VkBuffer` bound to the current pipeline.

Blocks with `uniform` are called _uniform blocks_, whereas blocks
with `buffer` are called _storage blocks_. Uniform blocks can
only be read from within a shader, whereas storage blocks can
both be read from and written to.

The syntax for declaring an interface block is an optional layout
qualifier, the storage qualifier(s), an identifier, `{`, one or
more uninitialized variable declarations not paired with a struct
definition, `}`, an optional identifier or array specifier, and
`;`. Here is an example:

```glsl
layout(binding=0, set=0) uniform material {
    flat int ndx;
    float rough;
    float metal;
} mats[5];
```

This declares a uniform block called `material` which groups
together three uniforms, `ndx`, `rough`, and `metal`. The
optional identifier after the block is called its _instance
name_, and if included the members are scoped into a namespace
under it. For instance, `mats[2].ndx` would be in scope after
this, but not plain `ndx`. However, if we had declared `material`
this way:

```glsl
layout(binding=0, set=0) uniform material {
    flat int ndx;
    float rough;
    float metal;
};
```

then `ndx`, `rough`, and `metal` would be globally scoped and
thus accessible anywhere in the shader.

A block member is allowed to be qualified with the same storage
qualifier used in its block; for instance, `ndx` above could have
been declared as `flat uniform int ndx;` with the same outcome.
This accomplishes nothing, though.

In `VkPhysicalDeviceLimits`,
`maxPerStageDescriptorUniformBuffers` and
`maxPerStageDescriptorStorageBuffers` indicate the maximum number
of uniform and storage buffers that can be made available to a
single shading stage, whereas `maxDescriptorSetUniformBuffers`
and `maxDescriptorSetStorageBuffers` indicate the maximum number
of uniform and storage buffers that can be included in a whole
pipeline layout. My graphics card supports 15 uniform buffers and
1,048,576 storage buffers per stage, and 180 uniform buffers and
1,048,576 storage buffers per pipeline layout. However, it only
supports 15 dynamic uniform buffers and 16 dynamic storage
buffers per stage (dynamic buffers can have an offset specified
at binding time).

A _shader interface_ consists of all the uniform blocks and
variables and storage blocks declared in the shader as well as
inputs/outputs at the boundary between two shading stages.

## Shaders

In the context of Vulkan, the spec describes shaders as
"[specifications of] programmable operations that execute for
each vertex, control point, tessellated vertex, primitive,
fragment, or workgroup in the corresponding stage(s) of the
graphics and compute pipelines" (see "[9.
Shaders](https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/vkspec.html#shaders)").
So, a vertex shader would be run for every vertex submitted to a
graphics pipeline (see "Drawing" under "Command Buffers").

Vulkan shaders have an _entry point_, which is the name of the
function where execution is meant to begin in the shader
(typically "`main`").

As a general rule, you should not make assumptions about the
order in which shader invocations will run, period. The most
significant exception is that a shader with inputs that depend on
previous pipeline stages will run after the operations needed to
generate those inputs.

### Language

Shader code used within Vulkan must be in either the
[SPIR-V](https://www.khronos.org/registry/spir-v/specs/unified1/SPIRV.html)
language, or the
[GLSL](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.pdf)
language in conformance with the
[`GL_KHR_vulkan_glsl`](https://github.com/KhronosGroup/GLSL/blob/master/extensions/khr/GL_KHR_vulkan_glsl.txt)
extension spec. SPIR-V is specified in a binary format and
intended to be fast to compile, whereas GLSL is intended to be
relatively easy for human programmers to read and write. The
reference compiler for GLSL is The Khronos Group's
[`glslang`](https://www.khronos.org/opengles/sdk/tools/Reference-Compiler/),
which is capable of outputting SPIR-V binaries. Microsoft's
[`dxc`](https://github.com/Microsoft/DirectXShaderCompiler),
which takes
[HLSL](https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl)
input, also supports a SPIR-V target.

For the best performance, it is generally a good idea to use
SPIR-V shader code in Vulkan at runtime rather than GLSL code, as
GLSL is likely to be more time-consuming for the graphics driver
to compile.

### Modules

_Shader modules_ are Vulkan objects used to wrap shader code.
They are attached to pipelines during pipeline creation (see
"Initialization" under "Pipelines").

The function to create a shader module is
[`vkCreateShaderModule()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateShaderModule.html).
This utilizes a
[`VkShaderModuleCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkShaderModuleCreateInfo.html),
which mainly takes a pointer to the code and the size of the code
in bytes. If you are using a validation cache, you can add it to
this struct's `pNext` chain to make use of it with the module in
question (see "Validation cache" below for the specifics).

To destroy a shader module, use
[`vkDestroyShaderModule()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyShaderModule.html).
It's okay to call this while pipelines created with the module in
question are still in use.

### Inputs and outputs

Shaders can receive data via _inputs_ and pass on data via
_outputs_. In SPIR-V terms, this is via variables with input or
output storage class; in GLSL, this is via variables specified
with the `in` or `out` storage qualifiers. Shaders can have both
built-in and user-specified inputs and outputs.

### Variants

#### Vertex shaders

Vertex shaders run once per vertex and operate on that vertex and
its associated vertex attribute data (see below). Each outputs a
vertex and associated data (if any). Graphics pipelines must
include a vertex shader unless they are running in mesh shading
mode, and this shader is always run first in the pipeline.

##### Attributes

_Vertex attributes_ are a way for vertex shaders to receive data
through input variables. In the shader, each input variable
is associated with a _vertex input attribute number_. These
correspond to _vertex input bindings_ in a graphics pipeline. The
command `vkCmdBindVertexBuffers()` can be used to update the
vertex input bindings of a bound graphics pipeline with values
from `VkBuffer`s, making them available to the vertex shader
invocations (see "Binding to a command buffer" under "Command
buffers").

That all sounds rather abstract and confusing, so let's consider
an example. Say we have the following declaration in a GLSL
vertex shader:

```glsl
layout(location = 1) in vec4 color;
```

In this case, the input variable `color` has the vertex input
attribute number `1`.

Now, say we're using this shader in a C++ program where we've
declared a constant with this vertex input attribute number and a
vector with color information for each vertex (using
[Eigen](https://eigen.tuxfamily.org/index.php?title=Main_Page)'s
[`Vector4f`](https://eigen.tuxfamily.org/dox/group__matrixtypedefs.html)):

```cpp
// you can use SPIRV-Reflect
// (https://github.com/KhronosGroup/SPIRV-Reflect)
// to avoid the duplication here
constexpr uint32_t color_attr_n = 1;

std::vector<Eigen::Vector4f> vert_colors {
    {0.0, 1.0, 0.0, 1.0},
    // etc...
};
```

and assume we've moved this data into a `VkBuffer` called
`vert_colors_buff` and specified an offset into it for the draw
call:

```cpp
VkBuffer vert_colors_buff;
// copy vert_colors data into vert_colors_buff

VkDeviceSize colors_buff_offset = 0;
```

Now say we've started recording to a `VkCommandBuffer` called
`command_buff`. We've started a render pass and bound a graphics
pipeline created with the vertex shader we described above and
the applicable vertex input binding. To make our color
information available during vertex shading in this graphics
pipeline, we can call

```cpp
vkCmdBindVertexBuffers(command_buff,
                       color_attr_n,         // the input binding to start with
                       1,                    // the number of bindings to update
                       &vert_colors_buff,
                       &colors_buff_offset);
```

This will make the proper `vec4` of color information we first
stored in `vert_colors` available in the `color` input variable
for each invocation of our vertex shader.

For more information, see "[22. Fixed-Function Vertex
Processing](https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/vkspec.html#fxvertex)"
in the Vulkan spec and "[4.4 Layout
Qualifiers](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#layout-qualifiers)"
in the GLSL spec.

#### Tessellation control shaders

Vertices leaving the vertex shading stage are organized into sets
of vertices called _patches_. These become _input patches_ into
the tessellation section of the graphics pipeline if tessellation
is enabled for that pipeline. (The number of points in a patch is
configurable via
[`VkPipelineTesselationStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineTessellationStateCreateInfo.html)
during graphics pipeline creation.) The tesselation control
shading stage receives these input patches and produces output
patches for the tesselation evaluation stage. A single
tesselation control shader invocation runs for each control point
of an output patch; if output patches were set in the shader to
have four control points, each input patch would produce four
tesselation control shader invocations, each operating on that
input patch.

A tesselation control shader can specify how many control points
go into an output patch, and thus can add extra vertices that
were not present during vertex shading or discard some vertices.
This can be used to add interpolating points between the vertices
coming into the graphics pipeline, or even perform complex
modifications to the vertex data. It can also specify the amount
of tesselation at the edge (outer) and in the interior (inner)
performed on primitives before the tesselation evaluation stage.

#### Tessellation evaluation shaders

Between tessellation control and tessellation evaluation,
abstract primitives are assembled from the patches output by the
tesselation control stage. After this, the tessellation
evaluation shader is responsible for actually specifying the
position and other data associated with the vertices in the
abstract primitive.

They are able to control some aspects of how the tessellation
primitive generator operates, such as the kind of primitives
that are assembled and the spacing of the vertices.

#### Geometry shaders

Geometry shaders take primitives as input, either from automatic
primitive assembly as dictacted during graphics pipeline creation
or as produced by the tessellation stages if tessellation is
enabled.

If tessellation is not enabled, they are able to control the
type of primitive they receive as input, similarly to the
tessellation evaluation shader. They are also able to control the
number of times they run per primitive.

#### Fragment shaders

In a graphics pipeline, after vertex processing occurs (which
includes the tesselation and geometry stages if used), some
vertex post-processing such as primitive clipping occurs. After
that, the rasterization stage produces fragments from the vertex
data, which are data associated with rectangular framebuffer
regions (more on this in the graphics pipeline section). A
fragment shader invocation receives one of these fragments as
input and outputs values that can be applied to framebuffer or
texture memory, like color information.

As a general rule, fragment shader invocations run in isolation
from each other, so any information they will need about the
scene as a whole will likely need to be prepared beforehand.

Although at least one fragment shader invocation will be produced
for each fragment, _helper invocations_ are also sometimes
generated to compute derivatives for non-helper invocations. This
happens implicitly when calling the GLSL texel lookup function
`texture()` and explicitly when calling the GLSL derivative
functions. These execute the same code as non-helper invocations,
but will not modify shader-accessible memory (so they won't
update the framebuffer or anything).

There are a few tests that can be performed prior to fragment
shading, such as the [discard rectangles
test](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#fragops-discard-rectangles)
and the [scissor
test](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#fragops-scissor),
which can discard fragments. In this case, non-helper fragment
shader invocations will not be produced for the discarded
fragments, although helper invocations may still be.

A fragment shader can use the GLSL
[`early_fragment_tests`](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#layout-qualifiers)
layout qualifier to also make per-fragment tests run prior to the
fragment shader instead of afterwards (see "[28. Fragment
Operations](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#fragops)"
for the specifics). In this case, any depth information computed
by the fragment shader is ignored, because [depth
testing](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#fragops-depth)
is done beforehand.

Fragment shader invocations may also not be run if the
implementation can determine that another fragment shader would
overwrite its output entirely, or if another fragment shader
discards its fragment and it doesn't write to any storage
resources.

If there are overlapping primitives, it is possible for more than
one fragment shader invocation to operate simultaneously for the
same pixel. In theory, you could use the [fragment shader
interlock](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#shaders-fragment-shader-interlock)
features to define sections of your shader that are guaranteed
not to run simultaneously. However, at the time of writing, [AMD
does not support these
features](https://github.com/GPUOpen-Drivers/AMDVLK/issues/108)
(see also
[`VK_EXT_fragment_shader_interlock`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_EXT_fragment_shader_interlock.html)
support for
[Linux](https://vulkan.gpuinfo.org/listdevicescoverage.php?extension=VK_EXT_fragment_shader_interlock&platform=linux) and
[Windows](https://vulkan.gpuinfo.org/listdevicescoverage.php?extension=VK_EXT_fragment_shader_interlock&platform=windows)—[macOS](https://vulkan.gpuinfo.org/listdevicescoverage.php?extension=VK_EXT_fragment_shader_interlock&platform=macos)
support is better as [MoltenVK supports it under Metal 2.0+ with
raster order
groups](https://github.com/KhronosGroup/MoltenVK/blob/master/Docs/MoltenVK_Runtime_UserGuide.md#interacting-with-the-moltenvk-runtime)).
In some cases an approach using multiple subpasses is a good
alternative.

##### Interpolation

The following discussion will proceed in GLSL terms for ease of
understanding, although in truth the Vulkan spec is concerned
with SPIR-V decorations.

Fragment shader input variables are typically interpolated from
a previous stage's outputs. _Interpolation qualifiers_ can be
used to control the manner in which interpolation is done for a
given input variable. With Vulkan, you can use at most one of the
interpolation qualifiers `flat` and `noperspective` for an input
variable.

`flat` implies no interpolation. Variables designated as `flat`
will have their value assigned based on a single provoking vertex
(see [21.1 "Primitive
Topologies"](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#drawing-primitive-topologies)).
Inputs that contain or consist of integers or double-precision
floats must be qualified as `flat`.

`noperspective` implies linear interpolation (for lines and
polygons, i.e. not points, naturally). To be precise, this uses
the following formula:

<p align='center'>
    <i>f</i> =
        (1 - <i>t</i>)<i>f<sub>a</sub></i> + <i>tf<sub>b</sub></i>
</p>

where _f_ is the value the variable takes on,
<i>f<sub>a</sub></i> and <i>f<sub>b</sub></i> are the start and
end points of the segment, and _t_ is defined as follows:

<p align='center'>
    <i>t</i> =
        【 (<b>p</b><sub><i>r</i></sub>
         - <b>p</b><sub><i>a</i></sub>)
        ・
         (<b>p</b><sub><i>b</i></sub>
         - <b>p</b><sub><i>a</i></sub>) 】
        ／
        【 ||<b>p</b><sub><i>b</i></sub>
         - <b>p</b><sub><i>a</i></sub>||<sup>2</sup> 】
</p>

where __p__<sub><i>r</i></sub> is the _(x,y)_ window coordinates
of the center of the fragment, __p__<sub><i>a</i></sub> is the
_(x,y)_ window coordinates of the start of the segment, and
__p__<sub><i>b</i></sub> is the _(x,y)_ window coordinates of the
end of the segment.

Input variables with neither of these qualifiers will behave as
if they had the `smooth` qualifier applied to them, which implies
_perspective-correct interpolation_. This uses the following
formula:

<p align='center'>
    <i>f</i> =
        【 (1 - <i>t</i>)<i>f<sub>a</sub></i>/<i>w<sub>a</sub></i>
        + <i>tf<sub>b</sub></i>/<i>w<sub>b</sub></i> 】
        ／
        【 (1 - <i>t</i>)/<i>w<sub>a</sub></i>
        + <i>t</i>/<i>w<sub>b</sub></i> 】
</p>

where _f_, <i>f<sub>a</sub></i>, <i>f<sub>b</sub></i>, and _t_
are as defined above, and <i>w<sub>a</sub></i> and
<i>w<sub>b</sub></i> are the clip _w_ coordinates of the start
and end points of the segment.

(These equations are from [the OpenGL
spec](https://www.khronos.org/registry/OpenGL/specs/gl/glspec46.core.pdf),
section 14.5.1 "Basic Line Segment Rasterization".)

###### Auxiliary storage qualifiers

_Auxiliary storage qualifiers_ `centroid` and `sample` can
additionally be used to control the location interpolated to when
multisample rasterization is being used. Without them, the value
may be interpolated anywhere within the fragment. (If
`rasterizationSamples` is
[`VK_SAMPLE_COUNT_1_BIT`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSampleCountFlagBits.html)
in
[`VkPipelineMultisampleStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineMultisampleStateCreateInfo.html),
the fragment center will be interpolated to regardless of
auxiliary storage qualifiers.)

With `sample`, a separate value will be assigned to the variable
for each covered sample in the fragment, and the value will be
sampled at the location of the individual sample.

With `centroid`, a single value may be assigned to the variable
for all samples in the fragment, but it will be interpolated at a
location that lies in both the fragment and the primitive being
rendered. Because this location may vary between neighboring
fragments, and derivatives may be computed based on differences
between neighboring fragments, derivatives of centroid-sampled
inputs may be less accurate than if `centroid` was not used.

#### Compute shaders

Compute shaders provide a mechanism for doing "generic"
computation in Vulkan. They run within a compute pipeline as
opposed to a graphics pipeline.

Compute shaders have no fixed-function outputs. However, they
have access to many of the same resources as other shaders, so
they can affect the outside world via changes to buffers, images,
etc.

Compute shader invocations operate in _workgroups_. A workgroup
is a collection of compute shader invocations executing the same
code, possibly in parallel. Compute shaders run in a _global
workgroup_ which is divided into a configurable number of _local
workgroups_ (GLSL compute shaders can use [workgroup size
qualifiers](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#layout-qualifiers)
for this purpose). Invocations within a local workgroup can share
data (e.g. through the GLSL
[`shared`](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#storage-qualifiers)
storage qualifier) and synchronize execution via barriers (e.g.
by using the GLSL function
[`barrier()`](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#shader-invocation-control-functions)).

#### Task and mesh shaders

These are both involved in mesh shading, which my GPU doesn't
support, so I'm not going to cover them.

#### Ray tracing, intersection, any-hit, miss, and callable shaders

These are all part of the ray tracing extensions. My GPU barely
supports ray tracing and can't really do it in real time. Since
I'm writing a game engine, I'm not going to cover these either.

## Resource descriptors
