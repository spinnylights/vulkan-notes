# Vulkan notes

The text of this file is made available under the [CC BY-SA
4.0](https://creativecommons.org/licenses/by-sa/4.0/legalcode)
license.

## Table of contents

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

A lot of what you do with Vulkan is just setting things up. When
you want to actually do something within the context you've
created, you generally perform what's called _command
submission_, where you submit a "command" to what's called a
_queue_ (`VkQueue`) using one of the `vkCmd*()` functions. In
order to do _that_, you need to get a queue handle (`VkQueue`
again) from the device using `vkGetDeviceQueue()`.
`vkGetDeviceQueue()` requires you to specify what _queue family_
you want your queue to come from. A queue family is a set of
queues that support certain kinds of operations, like running
compute shaders or drawing to the screen, and they're associated
with a physical device. Now that you have a physical device, you
almost certainly want to enumerate the properties of its queue
families so that you can obtain handles to queues and submit
commands to them. You can do this with
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
still pending on it.

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

In order to actually do work on a device with Vulkan, you have to
"submit commands" to the device instead of just asking it to do
things directly. To be more specific, you submit these commands
to Vulkan objects called _queues_ (`VkQueue`), and then the
device carries out your commands probably very soon.

This bit of indirection might seem a little oblique, but it makes
sense from a performance standpoint. For one, command submission
is a time-consuming operation; this approach allows you to
prepare many commands and then submit them to the device all in
one go. Also, this approach increases opportunities for
parallelism, as Vulkan allows commands to run simultaneously
unless you explicitly say otherwise (see "Synchronization,"
below).

When Vulkan creates a logical device, it prepares queues for it
as part of the process. You specify what sort of queues you'd
like using
[`VkDeviceQueueCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceQueueCreateInfo.html);
[`VkDeviceCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceCreateInfo.html)
has a parameter `pQueueCreateInfos` which holds an array of
these. The sorts of queues you can set up depend on the
underlying physical device (see "Queue families" under "Physical
devices" above).

Once the logical device has been created, you can retrieve
handles (`VkQueue`) to any of its queues via
[`vkGetDeviceQueue()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetDeviceQueue.html)
(or
[`vkGetDeviceQueue2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetDeviceQueue2.html),
if you want to retrieve a handle to a queue created with specific
[`VkDeviceQueueCreateFlags`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceQueueCreateFlags.html)).

In order to actually submit commands to a queue once you've got a
`VkQueue` handle, first you need what's called a _command pool_,
which you can allocate _command buffers_ from (see "Command
buffers" below). Once you have a command buffer, you "record"
commands into it using `vkCmd*()` functions, and then "submit"
it to the queue using queue submission commands such as
[`vkQueueSubmit2KHR()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit2KHR.html)
or
[`vkQueueSubmit()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueSubmit.html).
A queue submission command takes a target queue, a set of
_batches_ of work, and optionally a fence for Vulkan to signal
when everything is finished (see "Fences" under
"Synchronization"). Each batch (described by e.g.
[`VkSubmitInfo2KHR`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubmitInfo2KHR.html))
consists of zero or more semaphores for the device to wait on
before starting, zero or more command buffers for the device to
execute, and zero or more semaphores for Vulkan to signal
afterwards (see "Semaphores" under "Synchronization").

You free queues along with their logical device when you call
`vkDestroyDevice()` on the device in question.

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

### Optimal command usage

You can tell from revisions to the Vulkan spec, [statements like
this](https://youtu.be/e0ySJ9Qzvrs?t=1964), etc. that every
command recorded comes with overhead, sometimes significant
overhead, and as such it's a good idea to record as few commands
as you need to for whatever you're trying to accomplish. In
particuar, many command functions give you opportunities to batch
work, and you should always try to take advantage of this if you
can rather than recording the same command repeatedly.

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
on their index in the vertex buffer. The trouble with this is
that, during tessellation, a certain number of vertex buffer
elements will be needed to make up each primitive; for example,
in the most common case of triangles, you would need three
elements per primitive (we'll get into all this in detail later).
If you wanted to render a square then, you might think you would
need four vertices, one for each corner—but if you weren't using
an indexed draw command, you would actually need six elements in
your vertex buffers for this, because it takes two triangles to
make a square:

![A rectangle with overlapping
vertices.](pics/overlapping_verts.svg)

Unfortunately, two of the elements in your vertex buffers would
be redundant in this case, because they would perfectly duplicate
the data of two of the other elements. I've drawn the vertices in
question slightly offset from each other here, but in practice
they would perfectly overlap, bloating your vertex buffers and
thus slowing down your rendering process.

With an index buffer, you can specify the order in which to
assemble the vertices into primitives explicitly. The advantage
of this is that vertices can be reused, which avoids the need to
duplicate vertices used to assemble more than one primitive. Even
if you don't mind the extra overhead, the models output by 3D
modeling programs usually work this way, so it's worth getting
comfortable with indexed draws regardless.

In either case, the primitive toplogy in use dictates how the
vertices are assembled once an ordering is established.

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

### Dispatch (compute shaders)

If you want to run a compute shader, you can use one of the
`vkCmdDispatch*()` commands. These commands provoke work in the
_compute pipeline_ you've bound to the command buffer you're
submitting dispatch commands to (see "Pipelines" below—that's
what you actually put your compiled compute shaders in).

`vkCmdDispatch()` is the "default option." If you want to read
its parameters from a buffer at runtime, you can use
`vkCmdDispatchIndirect()`, and if you want to apply offsets to
the components of `gl_WorkGroupID`, you can use
`vkCmdDispatchBase()`.

#### [`vkCmdDispatch()`](https://www.khronos.org/registry/vulkan/specs/1.3-extensions/man/html/vkCmdDispatch.html)

The basic dispatch command is `vkCmdDispatch()`.  It's pretty
easy to call—aside from a command buffer, you just need to pass
the numbers of _local workgroups_ to dispatch in the X, Y, and Z
dimensions. But what does that mean, exactly?

In short, when you run a compute shader, Vulkan dispatches a
certain number of invocations of it that all run in parallel
(although there are ways to synchronize them). To be specific,
the number of invocations Vulkan dispatches is `groupCountX *
groupCountY * groupCountZ`, in terms of the parameters you pass
into `vkCmdDispatch()`. So, this is where you specify how many
invocations of your compute shader you'd like to run.

For example, let's say your compute shader applies a filter to a
3840 × 2160 pixel image, and you'd like to run an invocation for
each pixel. Given that you've assigned your command buffer to the
variable `comp_buff`, you could call `vkCmdDispatch()` as
`vkCmdDispatch(comp_buff, 3840, 2160, 1)`. This would dispatch
`3,840 * 2,160 * 1 == 8,294,400` invocations of your shader.

All of these invocations run in a _global workgroup_ together.
Invocations in the same global workgroup run in parallel. If you
need to synchronize the invocations somehow, or you want subsets
of them to be able to share information at runtime, you can
organize them into _local workgroups_, which also have a size in
X × Y × Z invocations just like global workgroups do. You
specify the size of the local workgroup in the compute shader
using the `local_size_x`/`y`/`z` layout qualifiers (see "In the
compute shader" under "Layout qualifiers" below).

The above `vkCmdDispatch(comp_buff, 3840, 2160, 1)` call for a
3840 × 2160 image assumes that each invocation has its own local
workgroup. Let's say your filter requires invocations to
collaborate within 4 × 4 squares of pixels, so you've set a local
workgroup size of 4 × 4 within the compute shader. The parameters
of `vkCmdDispatch()` specify the number of local workgroups to
dispatch, so in this case you could call
`vkCmdDispatch(comp_buff, 960, 540, 1)` (in other words, 3840 ×
2160 divided by 4).

#### [`vkCmdDispatchIndirect()`](https://www.khronos.org/registry/vulkan/specs/1.3-extensions/man/html/vkCmdDispatchIndirect.html)

Like the indirect draw commands, you can use
`vkCmdDispatchIndirect()` to read the dispatch parameters from a
buffer at runtime. It takes a buffer to read from and an offset
to start reading at, and it expects to find a
[`VkDispatchIndirectCommand`](https://www.khronos.org/registry/vulkan/specs/1.3-extensions/man/html/VkDispatchIndirectCommand.html)
struct at that offset with the number of local workgroups to
dispatch in the X, Y, and Z dimensions.

#### [`vkCmdDispatchBase()`](https://www.khronos.org/registry/vulkan/specs/1.3-extensions/man/html/vkCmdDispatchBase.html)

You can use `vkCmdDispatchBase()` if you want to apply offsets
to the components of `gl_WorkGroupID` as reported in the compute
shader (they start at (0, 0, 0) by default). In addition to the
normal `groupCountX`/`Y`/`Z` parameters, it also takes
`baseGroupX`/`Y`/`Z` parameters with the values for Vulkan to
start counting at when determining the workgroup ID of a given
invocation.

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

#### Image layouts

An image's layout describes how its data is arranged in memory at
a high level. We've touched on this a little bit already with
`VK_IMAGE_LAYOUT_UNDEFINED` and `VK_IMAGE_LAYOUT_PREINITIALIZED`.
Image subresources can have a lot of other layouts aside from
just those two, but they have to be _transitioned_ into them
post-initialization. This is done as part of a memory dependency
(see "Image layout transition" under "Memory barriers"). Places
where this can occur include the execution of a pipeline barrier
command (see "Recording" under "Pipeline barriers"), waiting on
an event (see "Device operations" under "Events"), or as part of
a subpass dependency (see "Render pass"). As a general rule,
image layout transitions are an optimization mechanism, as the
different layouts are mainly specified in terms of which usage
they are optimal for.

The layouts are enumerated in
[`VkImageLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageLayout.html).
In core Vulkan, aside from the layouts we've already discussed,
images can be laid out optimally for use as a color or
depth/stencil attachment, read-only sampled image for shader
access, or transfer source or destination. Various combinations
of optimized read-only vs. read-write access for components of a
depth/stencil attachment are supported. `VK_KHR_swapchain` also
provides a layout optimized for presentation.

In general, different subresources of the same image can have
different layouts. The only exception is that depth/stencil
aspects of a given image subresource must always be in the same
layout.

When accessing an image in Vulkan, the available mechanisms can't
detect which layout an image subresource is in, so you have to
keep track of this information and provide it as needed. The
rules are slightly relaxed when accessing just the depth or
stencil components of a subresource, in which case only the
layout relating to the accessed component needs to match (e.g.
`VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL` and
`VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL` would both be okay for
accessing just the depth component).

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

### Resource views

Views are a mechanism allowing access to texel-holding resources
from within shaders. There are different types for buffers and
images.

#### Buffer views

Buffer views are only supported for buffers created with the
`VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT` and/or
`VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT` usage flags. The view
specifies both the range and format of the data within the buffer
to access.

A buffer view is represented by a
[`VkBufferView`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBufferView.html)
handle. These are created via
[`vkCreateBufferView()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateBufferView.html),
which takes a
[`VkBufferViewCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBufferViewCreateInfo.html).
As was just alluded to, this specifies a range and offset for the
buffer data and a
[`VkFormat`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormat.html)
describing the texel format. The range can be given as
`VK_WHOLE_SIZE` to go from the offset to the end of the buffer;
if the resulting range is not a multiple of the format's block
size, the nearest smaller multiple will be used, so you may end
up short a texel from what you were expecting in that case.

To destroy a buffer view, use
[`vkDestroyBufferView()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyBufferView.html).
Any submitted commands that refer to the buffer in question must
have completed execution before you call this.

#### Image views

As you might imagine, image views are more baroque than buffer
views. There are different types of image view, depending on the
image's dimensionality, layer count, etc.; these are enumerated
in
[`VkImageViewType`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageViewType.html).
The image view itself is represented by
[`VkImageView`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageView.html);
this is created with
[`vkCreateImageView()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateImageView.html),
which takes a
[`VkImageViewCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageViewCreateInfo.html).
That includes a field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImage.html">VkImage</a>
image</a></code> from which the view will be created.

[Butler Lampson](https://en.wikipedia.org/wiki/Butler_Lampson)
famously said, "All problems in computer science can be solved by
another level of indirection." This is, of course, typically
appended with "...except for the problem of too many levels of
indirection." Here is the process by which an image is written to
from a fragment shader:

<pre>
                                                                ┌─────────┐
                                                                │         │
                                               ┌──────────────┐ │ Command │ ┌───────┐
                            You                │ Draw command ╞═╡         ╞═╡ Queue │
                            are                └──────────────┘ │ buffer  │ └───────┘
                            here                                │         │
                             ↓                                  └─╥─────╥─┘
             ┌───────┐ ┌────────────┐ ┌─────────────┐ ┌───────────╨─┐ ┌─╨────────┐
             │ Image ╞═╡ Image view ╞═╡ Framebuffer ╞═╡ Render pass ╞═╡          │
             └───────┘ └────────────┘ └─────────────┘ └─────────────┘ │ Graphics │
                                                                      │          │
                   ┌─────────────┐ ┌───────────────┐ ┌──────────────┐ │ pipeline │
                   │ shader.frag ╞═╡ Shader module ╞═╡ Shader stage ╞═╡          │
                   └─────────────┘ └───────────────┘ └──────────────┘ └──────────┘
</pre>

I'll leave you with whatever conclusions you may come to on this
matter, good or ill.

The role of the image view in this elaborate formula is mainly
to isolate a set of subresources from the image in question.
[`VkImageViewCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageViewCreateInfo.html)
has a field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageSubresourceRange.html">VkImageSubresourceRange</a>
subresourceRange</code> for this purpose. You might not want to
involve all the subresources of an image in a rendering process;
the image view lets you pick and choose.

An image view has a few other tricks of indirection up its
sleeve, too. For example,
[`VkImageViewCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageViewCreateInfo.html)
also has a field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkComponentMapping.html">VkComponentMapping</a>
components</code> which allows you to swizzle the components of
the color vector that will be passed into the shaders from the
image (although this must be the identity swizzle for storage
images, input attachments, framebuffer attachments, or a view
used with a combined image sampler with
Y′C<sub>B</sub>C<sub>R</sub> conversion enabled). There is also a
field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormat.html">VkFormat</a>
format</code> that can be used to view the subresources through a
different format than they actually have, albeit with some
caveats—the image must have been created with the
`VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT` flag and have a
[compatible](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#formats-compatibility-classes)
format with the format of the view (unless the image was created
with `VK_IMAGE_CREATE_BLOCK_TEXEL_VIEW_COMPATIBLE_BIT` and is in
a compressed format, in which case a view can be created from it
with an equivalent uncompressed format).

The
<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageViewType.html">VkImageViewType</a>
viewType</code> field that we briefly touched on has a bit of a
complicated relationship with the properties of the underlying
image. Not every image supports every view type—see ["Table 16:
Image and image view parameter compatibility
requirements"](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#resources-image-views-compatibility)
in the Vulkan spec for how to properly set up a view for a given
image. The `baseArrayLayer` and `layerCount` fields in that chart
are part of the view's
[`VkImageSubresourceRange`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageSubresourceRange.html).

As with buffer views, image views are destroyed via
[`vkDestroyImageView()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyImageView.html),
which must be called only after commands that refer to the image
view have finished.

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
not be the ideal tool for your use case, and you have to
understand the nitty-gritty stuff about this topic in order to
get how to use it, but just know that if this seems like a
dizzying amount of work to tackle for one small part of the API
there is some help out there. We'll come back to it later after
we've explored memory management from the pure Vulkan
perspective.

All right, pull up yer sleeves folks!!

### Memory types

When you call
[`vkPhysicalDeviceMemoryProperties2()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceMemoryProperties2.html)
(or
[`vkPhysicalDeviceMemoryProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceMemoryProperties.html),
w/e), you get an array of
[`VkMemoryType`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkMemoryType.html)s,
which tell you about the types of memory available on the device
(surprise, surprise). These have the index of the memory heap the
memory type in question corresponds to, and also a bitmask of
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

Our `VkMemoryRequirements buf_mem_reqs` has a bitmask field
`memoryTypeBits` that has a bit set for each index of
`memoryTypes[]` corresponding to a memory type that can support
our `buffer`.

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
        bool fits_reqmnts = (memoryTypes[i].propertyFlags & reqs) == reqs;

        if (type_supported && fits_reqmnts) {
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
invalidating the relevant host cache range also needs to be
managed by the host to ensure that accesses to it are visible to
both the host and device. There are two functions provided for
this purpose,
[`vkFlushMappedMemoryRanges()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkFlushMappedMemoryRanges.html)
and
[`vkInvalidateMappedMemoryRanges()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkInvalidateMappedMemoryRanges.html).
`vkFlushMappedMemoryRanges()` ensures that host writes to the
specified memory ranges are made visible to the device, while
`vkInvalidateMappedMemoryRanges()` ensures that device writes to
the specified memory ranges are made visible to the host. It's
worth noting that unmapping non-host-coherent memory does not
flush the cache, nor does mapping non-host-coherent memory
automatically invalidate it—you have to take care of these things
while you're mapping and unmapping the memory.

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
  frequently-updated host-written data. Remember flushing and
  invalidating the host cache ranges if the memory is not
  host-coherent.
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

VMA comes as a header-only library. Thankfully it has no
dependencies aside from Vulkan. It's written in C++ but exposes a
C interface. If you're writing your application in C, this of
course means that you'll either need to compile VMA into a
regular, non-header-only library to link with or you'll need to
compile at least part of your codebase with a C++ compiler. VMA
assumes by default that you're statically linking with Vulkan,
but you can configure it otherwise, and also hand it the function
pointers it needs if you're loading Vulkan functions at runtime.
(See
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
from a given heap if you want, how many frames you need to keep
track of resources for if you're using the lost allocations
feature, etc.

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
API, if you want to sidestep `vmaCreate*`/`vmaDestroy*`.

It has some convenience functions for mapping memory. They're not
that different from the Vulkan interface, but they're a bit safer
(it's okay to call
[`vmaMapMemory()`](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/vk__mem__alloc_8h.html#ad5bd1243512d099706de88168992f069)
on an already-mapped memory object, for instance). It does take
care of basic synchronization and has a flag you can set if you
want to map the memory persistently, but you still need to take
care of flushing and invalidating the host cache ranges if it's
not host-coherent. See ["Memory
mapping"](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/memory_mapping.html)
in the VMA docs for more info.

There's no special support for binding a single large buffer and
storing different kinds of data in it by offset, like we talked
about in "Sub-allocating". You can allocate such a buffer with
VMA, but you have to take care of managing it afterwards.

When allocating a new block, VMA will automatically attempt to
allocate a smaller block than its (configurable) default size if
allocating a default-sized block would go over the memory budget.

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

It has a feature called "lost allocations" in which it can
automatically free the memory of resources that are guaranteed
not to be needed anymore. This can help ensure that available
memory is not exhausted. It does this based on how many frames
have passed since the resource was last accessed. You have to
configure how many frames resources should stay valid for, tell
it when a new frame starts, mark resources as "losable," and
query resources at the start of each frame to see if they're
still available. See ["Lost
allocations"](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/lost_allocations.html)
in the VMA docs for more info.

So, should you use VMA? That's a call you have to make. One of the
biggest complaints you might have about it is that you still have
to think about memory management in a lot of depth even if you
you do use it, and there are always costs associated with
bringing in any dependency. On the other hand, much of what it
does do are things that the average Vulkan application would end
up implementing in largely the same way, and it's very flexible,
so you can probably get it to work close to how your code would
have done in the places where you do use it (unless your
application is very unusual).

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
VMA is designed such that you can use it in a kind of piecemeal
fashion, so if you start out using it and later begin to feel
that it's an obstacle somewhere you can probably change just that
part of your codebase without having to pull out the library
entirely.

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
execution dependency encountered in Vulkan.

Some operations read from or write to locations in memory.
Memory dependencies between two operations guarantee that the
first operation will finish writing before the location it's
writing to is made _available_ to later operations, and that the
data is made _visible_ to the second operation before it begins.
An available value stays available until its location is written
to again or freed; if an available value becomes visible to a
type of memory access, it can then be read from or written to by
memory accesses of that type as long as it stays available.

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

Execution dependencies that are not memory dependencies cannot
guarantee that data which has been written by an operation will
be ready for reading by a later operation, or that one set of
data will be written to a location before another set of data is
written there.

### Memory access synchronization between device and host

Direct host access to memory that is not host-coherent generally
needs to be managed in conjunction with flushing and invalidating
the relevant parts of the host caches if the device also accesses
it. See "Memory types" and "Mapping memory" under "Memory
management" for more on these topics. These operations can be
synchronized appropriately by the use of memory barriers (see
"Memory barriers" below). Explicit synchronization is not
necessary in the following case, however.

If you write to device memory through a host-mapped pointer, then
submit a batch of command buffers, the device will be able to
read the changes the host made before submission, and if the
device writes to that memory during execution of the commands,
the host will be able to see the changes made by the device
afterwards. This is assuming that host caching behavior has been
managed appropriately if the memory is not host-coherent.

To be precise, when batches of command buffers are submitted to a
queue, a memory dependency is defined between host operations
that took place before the submission and the execution of the
submitted commands. The first synchronization scope for this
dependency is defined in part by the host execution model; it
includes the `vkQueueSubmit()` call and anything that happened
prior according to the host. The second synchronization scope
includes all the submitted commands and any commands submitted
afterwards. The first access scope includes all host writes to
mapped device memory, and the second access scope includes all
memory accesses performed by the device.

### Mechanisms

Earlier we said that Vulkan provides several mechanisms for
synchronization. To be specific, there are five: _semaphores_,
_fences_, _events_, _pipeline barriers_, and _render passes_. One
of these—render passes—we have already explored briefly, but we
will explore it in depth here. The others are new to us.

Before we get into the details, here's a table showing the rough
capabilities of each. "Queue" means between batches of command
buffers submitted to queue, whereas "Command" means within a
single command buffer. "Pipeline" means between pipeline stages,
whereas "buffer/image" means around buffer or image access. There
are no command-level ways to perform an unsignal operation, so
all the command-level signal operations mean "on".

<table>
    <tr>
        <th rowspan="3">Mechanism</th>
        <th colspan="4">Host</th>
        <th colspan="3">Queue</th>
        <th colspan="4">Command</th>
    </tr>
    <tr>
        <th colspan="2">Signal</th>
        <th rowspan="2">Wait</th>
        <th rowspan="2">Query</th>
        <th colspan="2">Signal</th>
        <th rowspan="2">Wait</th>
        <th colspan="2">Signal</th>
        <th colspan="2">Wait</th>
    </tr>
        <th>On</th>
        <th>Off</th>
        <th>On</th>
        <th>Off</th>
        <th>Pipeline</th>
        <th>Buffer/image</th>
        <th>Pipeline</th>
        <th>Buffer/image</th>
    <tr>
    </tr>
    <tr>
        <td>Semaphores (timeline)</td>
        <td>✔</td>
        <td>n/a</td>
        <td>✔</td>
        <td>✔</td>
        <td>✔</td>
        <td>n/a</td>
        <td>✔</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
    </tr>
    <tr>
        <td>Semaphores (binary)</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td>✔</td>
        <td>✔</td>
        <td>✔</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
    </tr>
    <tr>
        <td>Fences</td>
        <td></td>
        <td>✔</td>
        <td>✔</td>
        <td>✔</td>
        <td>✔</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
    </tr>
    <tr>
        <td>Events (w/ synchronization2)</td>
        <td>✔</td>
        <td>✔</td>
        <td></td>
        <td>✔</td>
        <td></td>
        <td></td>
        <td></td>
        <td>✔</td>
        <td>✔</td>
        <td>✔</td>
        <td>✔</td>
    </tr>
    <tr>
        <td>Events (w/out synchronization2)</td>
        <td>✔</td>
        <td>✔</td>
        <td></td>
        <td>✔</td>
        <td></td>
        <td></td>
        <td></td>
        <td>✔</td>
        <td></td>
        <td>✔</td>
        <td>✔</td>
    </tr>
    <tr>
        <td>Pipeline barriers</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td>✔</td>
        <td>✔</td>
    </tr>
    <tr>
        <td>Render passes</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td>✔</td>
        <td>✔</td>
    </tr>
</table>

As you can see, timeline semaphores overlap with the capabilities
of both binary semaphores and fences. They're also easier to work
with and potentially more efficient than either, so if they're
available to you they're always a good default for coarse-grained
synchronization.

For fine-grained synchronization, events are useful for when the
host needs to have some relationship with a specific operation
happening in the execution of a command buffer. If not, the
render pass and/or a pipeline barrier will probably carry less
overhead. Pipeline barriers can be used outside of a render pass;
within a render pass, they're just one of a variety of ways of
creating dependencies.

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
_timeline_; timeline semaphores were promoted from the extension
[`VK_KHR_timeline_semaphore`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_timeline_semaphore.html).
Earlier versions of Vulkan have only binary semaphores in their
core APIs. However, the
[Vulkan-ExtensionLayer](https://github.com/KhronosGroup/Vulkan-ExtensionLayer/)
provides support for timeline semaphores even in environments
that otherwise wouldn't have it. Vulkan 1.0+ environments also
sometimes support timeline semaphores via the extension.

Binary semaphores have two states: signaled and unsignaled. When
you start to wait on a binary semaphore, it becomes unsignaled;
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
things). Like
[`VK_KHR_timeline_semaphore`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_timeline_semaphore.html),
you can use this extension even in environments that don't
support it by using the
[Vulkan-ExtensionLayer](https://github.com/KhronosGroup/Vulkan-ExtensionLayer/).
We'll look at how to work both with this extension as well as
the core API. The Khronos Group [encourages the use of this
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

As an alternative to waiting on a fence, you can also use
[`vkQueueWaitIdle()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueWaitIdle.html)
or
[`vkDeviceWaitIdle()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDeviceWaitIdle.html),
which are kind of like shorthands for fence operations.
[`vkQueueWaitIdle()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueWaitIdle.html)
just takes a queue to wait on, and is equivalent to submitting a
fence to that queue and waiting indefinitely for the fence to be
signaled.
[`vkDeviceWaitIdle()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDeviceWaitIdle.html)
just takes a device, and is equivalent to calling
[`vkQueueWaitIdle()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkQueueWaitIdle.html)
on every queue created with the device.


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
queue. However, they don't have internal state; they merely
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
which case the contents may be discarded. (See "Image layouts"
under "Images" for more on the layouts themselves.)

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

### Render passes

A _render pass_ provides a way to coordinate access to images
during rendering. Render passes are a more complicated
synchronization primitive than those we've discussed so far; they
play a significant role in rendering generally (as you might
imagine given their name). They're represented by a handle
[`VkRenderPass`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPass.html).

In a sense, render passes are like an object that stores
operations in a small declarative language you can use to
describe a rendering process at a high level. In fact, in
addition to being an object, they are also something you begin
and end in a command buffer (they are a synchronization
primitive, after all).

In Vulkan 1.2, the extension
[`VK_KHR_create_renderpass2`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_create_renderpass2.html)
was promoted to the core. This introduces `*2` versions of some
of the render-pass-related structs and functions. However, all
the new functionality they bring in relates to things we're not
covering (multiview,
[`VK_KHR_fragment_shading_rate`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_fragment_shading_rate.html),
[`separateDepthStencilLayouts`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPhysicalDeviceSeparateDepthStencilLayoutsFeatures.html)
which [has no macOS support at this
time](https://vulkan.gpuinfo.org/listfeaturescore12.php?platform=macos),
etc.). So, we're just going to cover the "traditional" render
pass interface.

Render passes can be created with
[`vkCreateRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateRenderPass.html),
which takes a
[`VkRenderPassCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPassCreateInfo.html).
This basically takes three arrays as parameters—a
[`VkAttachmentDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html)
array, a
[`VkSubpassDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDescription.html)
array, and a
[`VkSubpassDependency`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDependency.html)
array. Each of these types is fairly complex, so we'll take them
in turn.

Actually, wait. Before we do that, let's explore the render pass
as something you begin and end. I think it feels more solid that
way.

#### Render pass commands

A _render pass instance_ is what arises when you _begin_ a render
pass in a command buffer. You can begin a render pass with
[`vkCmdBeginRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBeginRenderPass.html).
Once the render pass instance is underway, you can move it from
_subpass_ to _subpass_ with
[`vkCmdNextSubpass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdNextSubpass.html);
a subpass is like a distinct phase of a render pass. Between
calls to this function, you can record drawing commands and the
like for each subpass (see "Drawing" under "Command buffers",
"Pipeline barriers" above, etc.). Once you've recorded all the
commands for the render pass, you can end the instance with
[`vkCmdEndRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdEndRenderPass.html).

Some commands can only be recorded within a render pass instance.
Aside from
[`vkCmdNextSubpass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdNextSubpass.html)
and
[`vkCmdEndRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdEndRenderPass.html),
these also include the drawing commands (see "Drawing" under
"Command buffers"), as well as
[`vkCmdClearAttachments()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdClearAttachments.html),
which is used to clear regions of attachments in the current
subpass. Some commands also have special meaning when recorded
within a render pass instance, such as those used to declare a
pipeline barrier (see "Pipeline barriers").

##### Beginning a render pass

[`vkCmdBeginRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBeginRenderPass.html)
must be recorded in a primary command buffer (see "Command
buffers").  It takes most of its parameters in a
[`VkRenderPassBeginInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPassBeginInfo.html).
This includes fields <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPassBeginInfo.html">VkRenderPass</a>
renderPass</code> and <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPassBeginInfo.html">VkFramebuffer</a>
framebuffer</code>, which specify the render pass and the
_framebuffer_ for the instance (a framebuffer in Vulkan is
basically a collection of image views). There's also a <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRect2D.html">VkRect2d</a>
renderArea</code> that defines the area rendering must be
confined to for all the images in the render pass, and an array
<code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkClearValue.html">VkClearValue</a>\*
pClearValues</code> that sets the color and/or depth/stencil
values to use if the image corresponding to the
[`VkClearValue`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkClearValue.html)
by _attachment number_ is set to be cleared on load (we'll come
back to attachments).

[`vkCmdBeginRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBeginRenderPass.html)
also has a parameter <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassContents.html">VkSubpassContents</a>
contents</code>.
[`VkSubpassContents`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassContents.html)
is an enum value which you can use to pick whether you'll record
commands for the first subpass in the primary command buffer or
if you'll record its commands in a secondary command buffer.
`VK_SUBPASS_CONTENTS_INLINE` is the first option;
`VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS` is the second. If
you pick `VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS`, the
only command you're allowed to execute on the primary command
buffer is
[`vkCmdExecuteCommands()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdExecuteCommands.html) until you move to the next subpass or end the render pass instance.

##### Moving to the next subpass

Once you've finished recording commands for the current subpass,
you can move to the next subpass with
[`vkCmdNextSubpass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdNextSubpass.html).
This has only one parameter, which is also <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassContents.html">VkSubpassContents</a>
contents</code>. As before, this allows you to switch between
recording the commands for the next subpass in the primary
command buffer or in a secondary commmand buffer.

##### Ending the render pass

This is the easiest part—all you need to do is call
[`vkCmdEndRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdEndRenderPass.html),
which takes no parameters aside from the command buffer to record
it on. The only thing to watch out for is that you have to have
moved through every subpass described when the render pass was
created (more on this later).

#### Framebuffers

I promise we'll come back to render pass creation soon, but first
I think we should explore the framebuffer. All this stuff is
too confusing without the framebuffer.

A framebuffer is a collection of _attachments_, which are
basically image views (see "Images views" under "Images"). Well,
okay, not really, but in the context of the framebuffer, they
are. You'll see what I mean in just a moment. Framebuffers are
represented by
[`VkFramebuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFramebuffer.html)
handles, and created with
[`vkCreateFramebuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateFramebuffer.html),
which takes a
[`VkFrameBufferCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFramebufferCreateInfo.html).

[`VkFrameBufferCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFramebufferCreateInfo.html)
is relatively simple. As was just alluded to, it has an array
field <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageView.html">VkImageView</a>\*
pAttachments</code> where the attachments themselves are passed.
So what makes it more than just an image view array? Probably the
most significant other field is <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPass.html">VkRenderPass</a>
renderPass</code>, which defines what render passes the
framebuffer is _compatible with_. We'll define what that means a
bit later, as render pass compatibility is a general concept that
graphics pipelines also need to adhere to.

[`VkFrameBufferCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFramebufferCreateInfo.html)
also has `uint32_t` fields `width`, `height`, and `layers` that
define the rendering area for a subpass associated with the
framebuffer. Obviously the image subresources represented by the
views have their own dimensions, as does the render pass
instance; these fields should not exceed those, but they can
restrict rendering to a portion of them.

So. Okay. We have an array of image views, and a set of
dimensions describing some subsection of them. We also have a
render pass, although the framebuffer is coupled to it a bit
loosely—rather than being strongly associated with that
particular render pass, the framebuffer is created as _compatible
with_ that render pass, and perhaps other sufficiently similar
render passes.

Oh. Before we go, we should note that framebuffers have a
<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFramebufferCreateFlagBits.html">VkFramebufferCreateFlagBits</a>
flags</code> field with one flag:
`VK_FRAMEBUFFER_CREATE_IMAGELESS_BIT`, which says the framebuffer
has no image views. Psych!! Well, okay, okay, it's not really
_that_ surprising—arrays can be empty, after all. If this flag is
set, the framebuffer in question exists only to specify
dimensionality and attachment compatibility information for the
render pass. Mysterious…

As a side note, something a bit funny—framebuffers are also a
concept in hardware, if you can believe it given what we
discussed just now. That must already be obvious to some of you I
guess, but anyway, these are memory chips for the Sega Saturn's
video processors that contain framebuffers:

<a href="pics/2560px-Sega-Saturn-US-Motherboard-M2-03.png">
    <img
        src="pics/2560px-Sega-Saturn-US-Motherboard-M2-03.png"
        alt="An NTSC Sega Saturn VA2 ('VA-SG') motherboard with the
             Hitachi HM5221605TT17S memory chips for the VDP1+2 highlighted."
        width="800"
        height="527"
    >
</a>

From doing a bit of Saturn romhacking, I have to say, these kinds
of framebuffers are _much_ more like what you would expect when
you hear the word "framebuffer". They are blocks of memory where
you write a bitmap that is displayed on the screen. I feel like
the `VkFramebuffer` is related to these in perhaps a poetic
sense. Imagine a chip like this that stores something which is
three degrees removed from a bitmap, or one that "exists only to
specify dimensionality and attachment compatibility information
for the render pass" so to speak. Hahaha!

You know, maybe this is not so different from Saturn programming
after all, what with its two CPUs and two different graphics
processors and stuff. I think learning to work with its graphics
hardware is honestly easier than learning Vulkan, though, if you
ever feel tempted by that. Maybe it would be fun to write a guide
like this for the Saturn sometime…that feels kind of nice to
fantasize about right now. Anyway.

##### Framebuffer regions

This is just a quick concept we need to define so we can use it
elsewhere. A _framebuffer region_ is a subset of the geometric
area of the framebuffer. It can either be a _sample region_,
which is a set of sample coordinates (x, y, layer, sample) within
the framebuffer, or a _fragment region_, which is a set of
fragment coordinates (x, y, layer) within the framebuffer.
Obviously we haven't talked about what a sample or a fragment is
yet, but just hold tight for a bit and we'll get there (you can
skip ahead to "Graphics pipelines" if you need to know right
now). At this point you can just think about a framebuffer region
as some part of the image data included in the framebuffer.

#### Creating a render pass

At last! I think now we can approach this and it won't seem so
dizzyingly abstract. Just to quickly recap, a render pass is
represented by a
[`VkRenderPass`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPass.html)
handle, which is created with [`vkCreateRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateRenderPass.html),
which takes a
[`VkRenderPassCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPassCreateInfo.html),
which mainly stores a
[`VkAttachmentDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html)
array, a
[`VkSubpassDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDescription.html)
array, and a
[`VkSubpassDependency`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDependency.html)
array. We'll go through each of these one-by-one.

##### Attachment descriptions

Now that we've talked about what attachments are in the context
of a framebuffer (image views), we can start talking about
attachments from the point of view of the render pass as a whole.
Outside of the framebuffer, attachments are a sort of weird,
nebulous-feeling thing, represented by a couple of different
structures.
[`VkAttachmentDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html)
is one of them. It doesn't actually have a "constructor"—it's
basically a set of parameters for the render pass. I feel like it
might have been better off being named `VkAttachmentProcess`, as
its main function is to describe the process the attachment goes
through over the course of the render pass.

Four important fields in
[`VkAttachmentDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html)
are <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentLoadOp.html">VkAttachmentLoadOp</a>
loadOp</code>, <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentStoreOp.html">VkAttachmentStoreOp</a>
storeOp</code>, <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentLoadOp.html">VkAttachmentLoadOp</a>
stencilLoadOp</code>, and <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentStoreOp.html">VkAttachmentStoreOp</a>
stencilStoreOp</code>. These describe the _load_ and _store
operations_ associated with the attachment in the render pass.
The attachment's load operations execute as part of the first
subpass that uses it, and its store operations execute as part of
the last subpass that uses it. (I know we haven't really gotten
to subpasses yet—for now you can just think of them as phases of
the render pass.)

Thankfully
[`VkAttachmentLoadOp`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentLoadOp.html)
and
[`VkAttachmentStoreOp`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentStoreOp.html)
are pretty simple.
[`VkAttachmentLoadOp`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentLoadOp.html)
gives you a rather clever choice:

* `VK_ATTACHMENT_LOAD_OP_LOAD`, meaning you want to preserve the
  contents of the image within the render area;
* `VK_ATTACHMENT_LOAD_OP_CLEAR`, meaning you explicitly want to
  clear the contents of the image within the render area;
* `VK_ATTACHMENT_LOAD_OP_DONT_CARE`, meaning you don't care
  whether or not the image gets cleared or not on load.

I really like this part of the API…I feel like it has a nice
humanist quality. (You know, I wonder if like, if we make contact
with space aliens someday, if it will make sense anymore after
that to use the word "humanist" in that kind of context? Who can
say I suppose…I guess from our perspective it really depends on
the space aliens.)

[`VkAttachmentDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html)
also has a small collection of "routine fields". These are

* <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormat.html">VkFormat</a>
  format</code>, which specifies the format of the attachment in
  the image view sense,
* <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html">VkSampleCountFlagBits</a>
  samples</code>, which specifies how many samples the image in
  question has, and
* <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html">VkAttachmentDescription</a>
  flags</code>, which supports a single
  `VK_ATTACHMENT_DESCRIPTION_MAY_ALIAS_BIT` flag which indicates
  that the attachment aliases memory also occupied by other
  attachments.

There is a also a familiar face here in
[`VkAttachmentDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentDescription.html):
[`VkImageLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageLayout.html),
which types the remaining two fields, `initialLayout` and
`finalLayout`. (Nice to see a familiar face.) This is also easy
to understand: here we can declare an image layout transition
(see "Image layout transition" under "Memory barriers" above).
I'd be kind of surprised if you remembered but we briefly touched
on this in "Image layouts" when I mentioned that an image layout
transition can be done "as part of a subpass dependency."

##### Subpass descriptions

A _subpass_, described by one of the
[`VkSubpassDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDescription.html)s
in
[`VkRenderPassCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkRenderPassCreateInfo.html),
is a distinct phase of a rendering process in which a subset of
the attachments in the render pass are accessed (in the memory
sense). Every rendering command in a render pass is recorded in
one of its subpasses, as we explored a little bit in "Render pass
commands".

It's maybe a bit sneaky, but actually the subpass has a secret
identity: it brings us very close to writing shaders, and in a
way that starts to reveal the "true nature" of attachments beyond
just being image views. The attachments referenced in a
[`VkSubpassDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDescription.html)
have a relationship to the fragment shader that's run in the
subpass (if there is one):

* the <code>const <a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentReference.html">VkAttachmentReference</a>\*
  pInputAttachments</code> are available as _subpass inputs_
  within the fragment shader (see "Layout qualifiers" in
  "Shaders: Vulkan and GLSL"),
* the <code>const <a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentReference.html">VkAttachmentReference</a>\*
  pColorAttachments</code> are available as outputs in the
  fragment shader (see "Layout qualifiers" in "Shaders: Vulkan
  and GLSL"), and
* the <code>const <a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentReference.html">VkAttachmentReference</a>\*
  pDepthStencilAttachment</code> is used for stencil and depth
  testing during fragment shading (see "Stencil test" and "Depth
  test" under "Fragment operations"). The results of these tests
  can be made available as input to the fragment shader, and the
  attachment itself can also be read and written to from the
  fragment shader.

Vulkan doesn't allow you to declare an attachment as both a color
and a depth/stencil attachment. You can declare an attachment as
both an input and a color _or_ depth/stencil attachment, but you
have to be careful not to cause a data race (see "Subpass
feedback loops").

The <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentReference.html">VkAttachmentReference</a>\*
pResolveAttachments</code> are used to store the results of
_multisample resolve_ operations within the subpass, which we'll
discuss shortly.

`const uint32_t* pPreserveAttachments` is for attachments that
aren't used in this subpass but whose contents must be preserved
during it.

There is also a simple field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineBindPoint.html">VkPipelineBindPoint</a>
pipelineBindPoint</code> which specifies which type of pipeline the
subpass supports (`VK_PIPELINE_BIND_POINT_GRAPHICS` or
`VK_PIPELINE_BIND_POINT_COMPUTE`).

So, here you have a way of passing color, depth, and stencil
input to a fragment shader. There are other ways of getting
things into shaders, but this is a significant one in the
fragment shading context. Even more significantly perhaps, this
is where you specify images for a fragment shader to write to.
This is also part of how you set up multisampling, and has a way
to ensure that some attachments are not changed during part of a
render pass.

##### Subpass dependencies

_Subpass dependencies_, represented by
[`VkSubpassDependency`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDependency.html),
are the part of the render pass where its "synchronization
primitive" aspect is brought out most fully. They can be used to
define synchronization and access scopes between subpasses in the
render pass (see "Scopes and dependencies"). This is done by
specifying a source and destination subpass and setting a series
of flags.

Unless the subpass dependency chain within a render pass implies
otherwise, its subpasses may execute concurrently. If you
require part of a render pass to have finished before another
part, you can use subpass dependencies to ensure this. Be careful
that you are defining the narrowest dependencies possible in this
case, however, in order to maximize opportunities for
parallelism.

###### Source and destination subpasses

The source and destination subpasses are represented by `uint32_t
srcSubpass` and `uint32_t dstSubpass` respectively. You can set
these either to subpass indices or to `VK_SUBPASS_EXTERNAL`,
which refers to commands entered before or after the render pass
instance.

If `srcSubpass` and `dstSubpass` are set to different subpass
indices in the render pass, an execution dependency is
established between them, including a memory dependency. Its
scopes include all the commands submitted as part of each subpass
as well as any load, store, or multisample resolve operations
performed during either.

If `srcSubpass` and `dstSubpass` are set to the same subpass
index, a _subpass self-dependency_ is established for the
specified subpass. This does not establish an execution
dependency by itself, but rather allows for the declaration of
pipeline barriers within the subpass (see "Pipeline barriers").

If either `srcSubpass` or `dstSubpass` is set to
`VK_SUBPASS_EXTERNAL`, the execution dependency includes all the
commands occurring either before or after the subpass for the
scope in question.

###### Subpass dependency flags

The other fields in
[`VkSubpassDependency`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSubpassDependency.html)
are all bitmasks used to qualify the dependencies it creates.

<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineStageFlagBits.html">
VkPipelineStageFlags</a> srcStageMask</code> and <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineStageFlagBits.html">
VkPipelineStageFlags</a> dstStageMask</code> limit its
synchronization scopes to the specified pipeline stages, and
<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAccessFlagBits.html">VkAccessFlags</a>
srcAccessMask</code> and <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAccessFlagBits.html">VkAccessFlags</a>
dstAccessMask</code> limit its access scopes to the specified
access types.

<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDependencyFlagBits.html">VkDependencyFlags</a>
dependencyFlags</code> is a typical "random assorted flags"
field. The main important flag here is
`VK_DEPENDENCY_BY_REGION_BIT`, which declares the dependencies in
the subpass to be _framebuffer-local_. Provided that the
dependencies encompass only framebuffer-space pipeline stages
(see "Framebuffer-space stages" under "Graphics pipelines"), this
means that the dependencies will only concern the framebuffer
_region_ accessed by the current fragment shader instance (see
"Framebuffer regions" under "Framebuffers"). Without this flag,
the dependencies will be _framebuffer-global_, meaning they
concern the space of the framebuffer as a whole (unless they
involve non-framebuffer-space pipeline stages, in which case they
are neither framebuffer-local nor -global). If you need to read
the result of a previous color attachment output from a fragment
shader within the same render pass, and you only need to read the
value relating to the current fragment, you should set this flag,
because it will allow for greater GPU parallelism.

###### Image layout transitions implied by a subpass dependency

For attachments within the render pass, a subpass dependency is
similar to an image memory barrier (see "Memory barriers") with
matching stage and access masks, no queue family ownership
transfer, and the old and new layouts defined in accordance with
the layouts specified in the attachment's description.

If a subpass dependency is not declared between
`VK_SUBPASS_EXTERNAL` and the first subpass in the render pass,
and the description for an attachment within the first subpass
implies a transition away from its `initialLayout`, an implicit
subpass dependency exists as if declared like this:

```cpp
VkSubpassDependency implicit_start = {
    .srcSubpass      = VK_SUBPASS_EXTERNAL;
    .dstSubpass      = first; // index of the first subpass
    .srcStageMask    = VK_PIPELINE_STAGE_NONE_KHR;
    .dstStageMask    = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    .srcAccessMask   = 0;
    .dstAccessMask   = VK_ACCESS_INPUT_ATTACHMENT_READ_BIT
                       | VK_ACCESS_COLOR_ATTACHMENT_READ_BIT
                       | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
                       | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT
                       | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    .dependencyFlags = 0;
};
```

Similarly, if a subpass dependency is not declared between the
last subpass and `VK_SUBPASS_EXTERNAL`, and the description for
an attachment within the last subpass implies a transition into
its `finalLayout`, an implicit subpass dependency exists as if
declared like this:

```cpp
VkSubpassDependency implicit_end = {
    .srcSubpass      = last; // index of the last subpass
    .dstSubpass      = VK_SUBPASS_EXTERNAL;
    .srcStageMask    = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    .dstStageMask    = VK_PIPELINE_STAGE_NONE_KHR;
    .srcAccessMask   = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
                       | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    .dstAccessMask   = 0;
    .dependencyFlags = 0;
};
```

##### Subpass feedback loops

If a subpass uses an attachment as both an input attachment and a
color or depth/stencil attachment, the possibility exists for
a data race.

This is prevented if the components you read via the input
attachment are entirely different to those you write via the
color or depth/stencil attachment. In this case, either you have
to configure the graphics pipeline to prevent writes to color and
depth/stencil components that are also read as input, or you have
to use the attachment as only an input and depth/stencil
attachment and not write to it via the depth/stencil attachment.

Otherwise, the only way to prevent this data race is to use a
pipeline barrier for every time you read a value at a particular
sample coordinate in a fragment shader invocation if you wrote to
that value since either the most recent pipeline barrier or the
start of the subpass.

##### Attachment layout requirements

If an attachment is used as…

* …an input attachment only, it must be in the
    * `VK_IMAGE_LAYOUT_SHARED_PRESENT_KHR`,
    * `VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL`, or
    * `VK_IMAGE_LAYOUT_GENERAL` layout.
* …a color attachment only, it must be in the
    * `VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_SHARED_PRESENT_KHR`, or
    * `VK_IMAGE_LAYOUT_GENERAL` layout.
* …a depth/stencil stencil attachment only, it must be in the
    * `VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_STENCIL_ATTACHMENT_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_STENCIL_READ_ONLY_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_SHARED_PRESENT_KHR`,
    * `VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL`, or
    * `VK_IMAGE_LAYOUT_GENERAL` layout.
* …both an input and a color attachment, it must be in the
    * `VK_IMAGE_LAYOUT_SHARED_PRESENT_KHR`, or
    * `VK_IMAGE_LAYOUT_GENERAL` layout.
* …both an input and a depth/stencil attachment, it must be in
  the
    * `VK_IMAGE_LAYOUT_SHARED_PRESENT_KHR`,
    * `VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL`,
    * `VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL`, or
    * `VK_IMAGE_LAYOUT_GENERAL` layout.

See "Image layouts" for more on these.

#### Destroying a render pass

You can destroy a render pass with
[`vkDestroyRenderPass()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyRenderPass.html).
After everything we've discussed here, it's refreshingly simple.
Make sure all the commands referring to the render pass have
finished beforehand.

#### Render pass compatability

Sorry to leave you hanging about this. It just wouldn't have fit
in properly in the framebuffer section because it also has to do
with graphics pipelines. Both framebuffers and graphics pipelines
are "based on" (the spec's words) a specific render pass, which
defines the render passes they can be used with.

So, first off, two attachment references are compatible if they
have the same format and sample count, or are both
`VK_ATTACHMENT_UNUSED`, or the pointers to them are both null.

Two arrays of attachment references are compatible if all the
corresponding pairs of attachments between them are compatible.
If they're different lengths, the shorter one is treated as if
it's padded out with `VK_ATTACHMENT_UNUSED`s.

Two render passes are compatible if all of their attachment
references are compatible (aside from the preserve attachments)
and they're otherwise identical aside from the initial and final
layouts in their attachment descriptions, the load and store
operations specified in their attachment descriptions, and the
image layouts in their attachment references.

Although, if two render passes each have only one subpass, the
compatibility requirements for their resolve attachment
references and their depth/stencil resolve modes are ignored.

A framebuffer is compatible with a render pass if it was created
with that render pass or one compatible with it. Same goes for a
graphics pipeline.

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

##### Framebuffer-space stages

There are four stages in the graphics pipeline that operate in
accordance with the framebuffer (see "Framebuffers" under "Render
passes"). These are:

* fragment shading,
* early fragment tests,
* late fragment tests, and
* color attachment output.

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
invocations operating in parallel, with synchronization between
these invocations generally being the programmer's
responsibility.

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
free software. What's more, the non-profit that maintains GLSL is
the same one that maintains Vulkan, so they've both been designed
to play nice together.

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
started. Circular reasoning?

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
<source_string_number>`, where `<line>` is a constant integral
expression and `<source_string_number>` is an optional constant
integral expression. If `<source_string_number>` is omitted the
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

These are handle types for accessing textures. They are specified
with an optional type prefix, the string `sampler`,
and one of a set of possible strings describing the kind of
resource the sampler is designed to access, in that order. Here's
a few examples:

```glsl
sampler1D              // 1D, single-precision floating point image
usamplerCube           // unsigned integer cube map
isamplerBuffer         // signed integer texel buffer
samplerCubeArrayShadow // single-precision floating point cube map array depth texture
```

If you don't use an `u` or `i` prefix, GLSL assumes the
underlying image data is in a single-precision floating point
format. If you use `u`, it means "unsigned integer format," and
if you use `i`, it means "signed integer format."

The set of possible strings following `sampler` is:

String        | Meaning                                              | In Vulkan
------        | -------                                              | ---------
`1`–`3D`      | 1–3D (i.e. `sampler2D` is for a 2D `float` texture)  | `VK_IMAGE_TYPE_1`–`3D` (see "Images" > "Creation" > "Layers")
`1`–`2DArray` | 1–2D array                                           | `VK_IMAGE_TYPE_1`–`3D`, `VkImageCreateInfo::arrayLayers > 1` (see "Images" > "Creation" > "Layers")
`2DMS`        | 2D multisample                                       | `VkImageCreateInfo::samples > VK_SAMPLE_COUNT_1_BIT`, etc. (see "Images" > "Creation" > "Samples")
`2DMSArray`   | 2D multisample array                                 | `VkImageCreateInfo::samples > VK_SAMPLE_COUNT_1_BIT`, `VkImageCreateInfo::arrayLayers > 1`, etc. (see "Images" > "Creation" > "Samples", "Layers")
`Cube`        | cube map                                             | `VkImageCreateInfo::flags & VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT == 1`, etc. (see "Images" > "Creation" > "Layers")
`CubeArray`   | cubemap array                                        | `VkImageCreateInfo::flags & VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT == 1`, `VkImageCreateInfo::arrayLayers > 1`, etc. (see "Images" > "Creation" > "Layers")
`Buffer`      | buffer                                               | `VkBufferCreateInfo::flags & VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT == 1` (see "Buffers")
\*`Shadow`    | shadow sampler variant; comes after `1`–`2D`, `1`–`2DArray`, `2DRect`, `Cube`, and `CubeArray` | `VkImageCreateInfo::format` is a depth image format such as `VK_FORMAT_D16_UNORM` (see "Images" > "Creation" > "Format")

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

##### Subpass inputs

These are handles for accessing subpass inputs within fragment
shaders. Their names all contain the string `subpassInput`. Like
sampler types, they can have a `u` or `i` prefix indicating
integer type, and otherwise are taken as single-precision
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
integer operand, the integer operand is implicitly converted to
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
linear algebra; e.g.:

```glsl
mat2x2 A = { { 1, 2 }, { 3, 4 } };
vec4 B = { 1, 2, 3, 4 };
mat4x2 C = A * B;

/* note that this matrix would normally be written
 *     /  4  8 12 16 \
 *     \  6 12 18 24 /
 */
C == { {  4,  6 },
       {  8, 12 },
       { 12, 18 },
       { 16, 24 } }; // true
```

You can do component-wise multiplication of matrices using the
function `matrixCompMult()` (see "Matrix functions").

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
built-in function `not()` that accepts a vector, however (see
"Vector comparison").

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
`greaterThan()`, `lessThanEqual()`, and `greaterThanEqual()` (see
"Vector comparison").

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
matrices and vectors, with the same syntax. In the case of
matrices, applying a single subscript as in `my_mat[n]` returns a
vector holding the values from the `n`th column of the matrix.
Vector subscripting is the same as for an array of equivalent
length.

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

You're likely to get the best performance if you branch based on
the value of specialization constants; see `constant_id` under
"Layout qualifiers" for more on this.

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

You can use this in a fragment shader to have Vulkan abandon the
current fragment. Within a fragment shader, if execution reaches
`discard`, Vulkan will immediately discard the fragment and won't
update any relevant buffers. If your shader has already written
directly to other buffers such as a shader storage buffer when
execution reaches `discard`, those writes will still take effect.

You would typically use `discard` within a conditional statement;
the GLSL 4.60.7 spec gives this example:

```glsl
if (intensity < 0.0)
    discard;
```

One way you might choose whether or not to discard a fragment is
by testing its alpha value. If you decide to do this, remember
that Vulkan performs coverage testing after fragment shading, and
the coverage test may change the alpha value.

##### `return`

This is the classic keyword for exiting functions à la C. You can
write an expression after `return` and the value of the
expression will become the return value of the function, as you
would probably expect.

As in C, you can use `return` to return early from `main()`. If
you do this in a fragment shader, note that the outcome will be
different than if you had used `discard`; with `return`, Vulkan
will still update buffers as normal based on the outputs you've
defined. If you use `return` from `main()` in a fragment shader
without defining any outputs, Vulkan will do the same thing as if
you had allowed execution to reach the _end_ of `main()` at that
point without defining any outputs.

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

### A brief glance at samplers

Samplers have come up a few times before now and they get a few
more mentions in the following section, so I figure we might as
well touch on them briefly just so they don't seem totally opaque
to you. They'll be easier to get into in detail when we're
exploring rendering in-depth, so this isn't going to be an
exhaustive exploration of them—just a brief summary so you have
some idea of what they are.

Samplers are objects for reading image data, usually texture data
specifically. Obviously you can also read image data directly,
but samplers facilitate things like MIP mapping and interpolated
magnification. They're represented by
[`VkSampler`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSampler.html)
handles and created with
[`vkCreateSampler()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateSampler.html),
which takes a
[`VkSamplerCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSamplerCreateInfo.html).

You can attach them to a pipeline, but you don't actually
associate them with an image at that time. Instead, you bind both
an image view and a sampler to the pipeline and bring them
together in a shader.

### Resource descriptors

Buffers, buffer views, image views, samplers, and combined image
samplers are made accessible to shaders via _resource
descriptors_. These are organized into _descriptor sets_, which
themselves are organized via _descriptor set layouts_, which are
then made available in a pipeline via a _pipeline layout_, which
is used in the creation of a pipeline (good grief!).

#### Descriptor types

##### Storage image

A _storage image_ (`VK_DESCRIPTOR_TYPE_STORAGE_IMAGE`) wraps a
`VkImage`/`VkImageView` pair and presents it to the shader as
"raw texel data." In precise terms, you can use load, store, and
atomic GLSL image functions like `imageLoad()`, `imageStore()`,
and `imageAtomicAdd()` on a GLSL image variable backed by a
storage image descriptor. GLSL represents them with types like
`image2D`.

You have to use the `VK_IMAGE_LAYOUT_GENERAL` layout for the
storage image's underlying image subresources.

If you want to perform load or store operations on the storage
image, Vulkan must include `VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT`
in the associated image view's format features. If you want to
perform atomic operations on the storage image, Vulkan must
include `VK_FORMAT_FEATURE_STORAGE_IMAGE_ATOMIC_BIT` in the
view's format features.

##### Sampler

A _sampler descriptor_ (`VK_DESCRIPTOR_TYPE_SAMPLER`) wraps a
sampler, apart from any particular image. GLSL represents them
with the types `sampler` and `samplerShadow`.

##### Sampled image

A _sampled image_ (`VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE`) wraps a
`VkImage`/`VkImageView` pair and presents it to the shader as
"sampleable color data." In precise terms, you can combine a GLSL
image variable backed by a sampled image with a GLSL sampler and
use it with GLSL's texture functions. GLSL represents them with
types like `texture2D`.

You have to use one of the following layouts for the
storage image's underlying image subresources:

* `VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL`
* `VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL`
* `VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL`
* `VK_IMAGE_LAYOUT_STENCIL_READ_ONLY_OPTIMAL`
* `VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL`
* `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL`
* `VK_IMAGE_LAYOUT_GENERAL`

Vulkan must include `VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT` in the
format features of the underlying image view.

##### Combined image sampler

A _combined image sampler_
(`VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`) wraps both a
sampler and image/view pair at the same time. GLSL represents
them with types like `sampler2D`.

You have to use one of the layouts Vulkan allows for sampled
images for the underlying image subresources of the combined
image sampler's image component (see "Sampled image" above).

In some environments, you'll get better performance from a
combined image sampler than you will if you use a separate
sampled image and sampler and bring them together in the shader,
according to the Vulkan spec.

##### Uniform texel buffer

A _uniform texel buffer_
(`VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER`) wraps a buffer/view
pair and presents it to the shader as "read-only formatted texel
data." You can access their data using `texelFetch()`. GLSL
represents them as `uniform textureBuffer` variables.

GLSL treats their data as image data for format purposes, so you
don't have to cast it into the right format in the shader. You
can specify the format in the buffer view and the buffer will
behave in the shader as if it was an image in the same format.

You should ensure that the image data within the buffer is in a
format with `VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT` set in
its `VkFormatProperties::bufferFeatures`.

##### Storage texel buffer

A _storage texel buffer_
(`VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER`) wraps a buffer/view
pair and presents it to the shader as "read/write formatted texel
data" (with some caveats). You can think of them as similar to
storage images, but with a buffer instead. They support load,
store, and atomic operations (again, with some caveats). GLSL
represents them as `uniform imageBuffer` variables.

Vulkan guarantees support for performing load operations on
storage texel buffers in all shader stages, provided that the
buffer format has `VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT`
set. However, Vulkan only guarantees support for stores and
atomic operations on storage texel buffers in compute shaders;
stores require `VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_BIT` and
atomic operations require
`VK_FORMAT_FEATURE_STORAGE_TEXEL_BUFFER_ATOMIC_BIT`. If the
physical device supports the `fragmentStoresAndAtomics` feature,
you can perform stores and atomic operations on storage texel
buffers from a fragment shader, and if it supports
`vertexPipelineStoresAndAtomics`, you can perform them from
vertex, tessellation, and geometry shaders.

##### Storage buffer

A _storage buffer_ (`VK_DESCRIPTOR_TYPE_STORAGE_BUFFER`) wraps a
buffer directly; you can consume them in a shader as a struct you
define. You can perform load, store, and atomic operations on
storage buffers (although you can only perform atomic operations
on struct members of certain types; see the atomic functions in
the GLSL stdlib section for the details). GLSL represents them
simply as `buffer` structs with an accompanying block.

##### Uniform buffer

A _uniform buffer_ (`VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER`) wraps a
buffer directly, like a storage buffer, but you can only perform
load operations on a uniform buffer. GLSL represents them as
`uniform` structs with an accompanying block.

##### Dynamic uniform buffer

A _dynamic uniform buffer_
(`VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC`) is almost the same
as a uniform buffer (see above), but you can specify an
additional offset into it when you're binding the descriptor set.

##### Dynamic storage buffer

A _dynamic storage buffer_
(`VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC`) is almost the same
as a storage buffer (see above), but like a dynamic uniform
buffer, you can specify an additional offset into it when you're
binding the descriptor set.

##### Inline uniform block

An _inline uniform block_
(`VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK`) is also very similar
to a uniform buffer (see above), but you allocate the storage for
it directly from the descriptor pool instead of associating it
with a separate buffer, and you write data to it when you update
its descriptor set. They were brought into core Vulkan with
version 1.3, and provided by `VK_EXT_inline_uniform_block` before
that. Most commonly, they're used for small sets of constant
data, similarly to push constants, but with the advantage that
you can reuse the same set of data across different drawing and
dispatch commands.

Generally, there's not too much space available for an inline
uniform block.
[`VkPhysicalDeviceInlineUniformBlockProperties::maxInlineUniformBlockSize`](https://www.khronos.org/registry/vulkan/specs/1.3-extensions/man/html/VkPhysicalDeviceInlineUniformBlockPropertiesEXT.html)
gives the limit in bytes, and it's 256 on about [half of the
platforms
surveyed on
gpuinfo.org](https://vulkan.gpuinfo.org/displaycoreproperty.php?core=1.3&name=maxInlineUniformBlockSize&platform=all)
as of June 2022, although some platforms provide as much as ~4
MB.

You can't aggragate inline uniform block descriptors into arrays.
When you specify the array size for an inline uniform block
descriptor, you're actually just specifying the binding's
capacity in bytes.

##### Input attachment

An _input attachment_ (`VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT`)
wraps an image/view pair and presents it to the shader as
"read-only framebuffer-local color data." You can perform
framebuffer-local load operations on an image presented through
an input attachment (i.e. load operations on the same fragment
position as in a previous subpass within the same render
pass). When you can use an input attachment, you may see better
performance from doing so, especially on tiling architectures.

You can use any format for an input attachment that you could use
for color or depth/stencil attachments. Like with those
attachments, you must have the underlying image subresources in a
layout that permits shader access.

#### Descriptor API overview

Descriptors themselves are not represented by a discrete object
in Vulkan. Descriptor sets are, but by an opaque handle
[`VkDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html),
and they don't have an associated "constructor" but rather are
allocated from a _descriptor pool_. I know, I know. Descriptor
pools are represented by
[`VkDescriptorPool`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPool.html)
handles, and are created via
[`vkCreateDescriptorPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDescriptorPool.html).
Once created, descriptor sets can be allocated from the pool with
[`vkAllocateDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateDescriptorSets.html),
which takes (among other things) a
[`VkDescriptorPool`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPool.html),
a
[`VkDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html)
array, and a matching
[`VkDescriptorSetLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayout.html)
array. The descriptor set layouts are created via
[`vkCreateDescriptorSetLayout()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDescriptorSetLayout.html),
which mainly involves a
[`VkDescriptorSetLayoutBinding`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html)
array, in which you can specify the number and type of
descriptors in the binding as well as the shader stages that will
access the bound resources. Once allocated, the data held by a
descriptor set can be updated with
[`vkUpdateDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkUpdateDescriptorSets.html),
which can write data from resources as well as from another
descriptor set. You can also use
[`vkUpdateDescriptorSetWithTemplate()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkUpdateDescriptorSetWithTemplate.html)
(we'll get there). Pipeline layouts are represented by
[`VkPipelineLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineLayout.html)
handles and created via
[`vkCreatePipelineLayout()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreatePipelineLayout.html),
which also involves a
[`VkDescriptorSetLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayout.html)
array (as well as an array of _push constant ranges_—we'll get to
push constants in just a bit). Everything is brought together
with
[`vkCmdBindDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindDescriptorSets.html),
which takes (among other things) a
[`VkPipelineLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineLayout.html)
and a
[`VkDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html)
array. Goodness gracious, here's a diagram:

[![Binding descriptor sets](pics/descriptors.svg)](pics/descriptors.svg)

Naturally, this is glossing over some of the details (ha!), but
hopefully it helps you get your bearings.

#### Descriptor set layouts

A descriptor set layout, respresented by
[`VkDescriptorSetLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayout.html),
is essentially an array of _descriptor bindings_, which you
specify when calling
[`vkCreateDescriptorSetLayout()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDescriptorSetLayout.html)
with an array of
[`VkDescriptorSetLayoutBinding`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html)s.
There's actually not much more to
[`vkCreateDescriptorSetLayout()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDescriptorSetLayout.html) than this;
[`VkDescriptorSetLayoutCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutCreateInfo.html)
also has `pNext` and `flags` fields but they're pretty ancillary
(we'll touch on them at the end of this section). As you can see
in the graph above, you don't actually bind any resources when
creating a descriptor set layout; you're basically describing the
structure that descriptor sets made with this layout will take
on.

One thing to note apart from the details of
[`VkDescriptorSetLayoutBinding`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html)
is that
[`VkDescriptorSetLayoutCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutCreateInfo.html)'s
`uint32_t bindingCount` does not actually have to match the
length of its <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html">VkDescriptorSetLayoutBinding</a>\*
pBindings</code> array, because of
[`VkDescriptorSetLayoutBinding`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html)'s
field `uint32_t binding`. We'll explain in detail shortly.

These are the fields in [`VkDescriptorSetLayoutBinding`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html):

* `uint32_t binding`: This is the binding's _number_, which is
  similar to an index; it can be anywhere from `0` to <code><a href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutCreateInfo.html">VkDescriptorSetLayoutCreateInfo</a>::bindingCount - 1</code>,
  although each binding should have a different number. In GLSL,
  the bound resource(s) can be accessed using the layout
  qualifiers `set` and `binding`, where `set` takes the index of
  the descriptor set and `binding` takes the same value as used
  here, i.e. `layout(set=2, binding=1)`.  We'll discuss this more
  in "Layout qualifiers."
* <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorType.html">VkDescriptorType</a>
  descriptorType</code>: This describes how the bound resource(s)
  will be presented to a shader. There is a wide variety of
  descriptor types, as you'll see if you click the link. We'll
  discuss them in detail after we've gone over GLSL qualifiers,
  so we can also talk about them from the GLSL side. One thing we
  should touch on here is that if you use
  `VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC` or
  `VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC`, you can specify
  offsets into these buffers dynamically at binding time, one for
  each element specified by `descriptorCount`.
* `uint32_t descriptorCount`: If you're going to bind an array,
  you can use this field to specify its size, which will also be
  its size in GLSL. Otherwise, this should usually be `1`. You
  can set it to `0`, but then nothing will be bound, meaning you
  should not access this binding from any shader. Bindings whose
  existence is implied by the size of <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutCreateInfo.html">VkDescriptorSetLayoutCreateInfo</a>::bindingCount</code>
  but don't correspond to any `binding` will be treated as having
  a `descriptorCount` of `0` and thus should not be used,
  although they may still consume memory when a descriptor set is
  allocated with this layout.
* <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkShaderStageFlags.html">VkShaderStageFlags</a>
  stageFlags</code>: This is the most straightforward field; it
  describes which shader stages will access this binding's
  resource(s).
* <code>const <a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSampler.html">VkSampler</a>\*
  pImmutableSamplers</code>: If you set `descriptorType` to
  `VK_DESCRIPTOR_TYPE_SAMPLER` or
  `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`, any
  [`VkSampler`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSampler.html)
  handles you reference here will be copied into this layout and
  used for this binding. These samplers will be treated as
  _immutable samplers_. You should avoid updating a
  `VK_DESCRIPTOR_TYPE_SAMPLER` descriptor with immutable
  samplers, and if you update a
  `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER` descriptor that has
  them, only its image views will change. You should wait to
  destroy the corresponding samplers until after your last use of
  this layout and any descriptor pools and sets you've made with
  it. If you leave this field null, you should make sure to bind
  the necessary sampler handles into any descriptor sets you make
  with this layout.

The other fields in
[`VkDescriptorSetLayoutCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutCreateInfo.html)
are
`const void* pNext` and <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutCreateFlags.html">VkDescriptorSetLayoutCreateFlags</a>
flags</code>. Nothing in `flags` is useful without various
extensions so we won't touch on it here. `pNext` can be a pointer
to a
[`VkDescriptorSetLayoutBindingFlagsCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBindingFlagsCreateInfo.html),
which holds an array of
[`VkDescriptorBindingFlags`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorBindingFlags.html),
one for each member of `pBindings`. These specify aspects of when
the associated descriptors can be updated and when they're
required to be valid, mostly in ways that allow for greater
concurrency:

* `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT`: You can update
  the descriptors after binding the set to a command buffer but
  before submitting the buffer to a queue; the update will not
  invalidate the buffer. Also, you can update multiple
  descriptors with this flag from multiple threads, although you
  should still update a single descriptor synchronously. This is
  even okay if the buffer itself is in another thread, although
  the descriptor set should not be reset or freed while you're
  doing this. Note that sets which include this binding should be
  allocated from pools with
  `VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT` set (see
  "Descriptor pools").
* `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT`: If you don't
  access the resources associated with these descriptors from the
  shaders in a given pipeline, the descriptors themselves don't
  need to be valid when you submit the command buffer that
  pipeline is bound to.
* `VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT`: You
  can update the descriptors while the command buffer you've
  bound them to is pending, provided that you won't use the
  descriptors in the buffer. If you've also set
  `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT` for these
  descriptors, you can even update them while the buffer is being
  executed. Even if not, you can still do this if you don't use
  the descriptors statically from any of the relevant shaders.
* `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT`: You'll
  set the size of this binding using
  [`VkDescriptorSetVariableDescriptorCountAllocateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetVariableDescriptorCountAllocateInfo.html)
  when you allocate a descriptor set with this layout, with its
  `descriptorCount` attribute forming an upper bound on this size
  rather than specifying it absolutely (see "Allocating
  descriptor sets"). You're only allowed to set this flag for the
  last binding in the layout (i.e. the one with the highest
  `binding` number), and you should still use `descriptorCount`
  for checks against device limits and so on.

Descriptor set layouts are destroyed with
[`vkDestroyDescriptorSetLayout()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyDescriptorSetLayout.html),
which doesn't really involve anything special.

#### Descriptor pools

A descriptor pool is a pool of memory that you can allocate
descriptor sets from. They're represented by
[`VkDescriptorPool`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPool.html)
handles and created with
[`vkCreateDescriptorPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDescriptorPool.html).

[`vkCreateDescriptorPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDescriptorPool.html)
takes its parameters in a
[`VkDescriptorPoolCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPoolCreateInfo.html).
The two main parameters in this structure are `uint32_t maxSets`,
which is the maximum number of descriptor sets that can be
allocated from the pool at one time, and an array <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPoolSize.html">VkDescriptorPoolSize</a>\*
pPoolSizes</code>.

[`VkDescriptorPoolSize`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPoolSize.html)
has two fields, <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorType.html">VkDescriptorType</a>
type</code> and `uint32_t descriptorCount`. Together they specify
an amount of memory to allocate: however much is needed for that
many descriptors of the specified type. If you add two different
members to `pPoolSizes[]` with the same `type`, enough memory
will be allocated for both.

`maxSets` and `pPoolSizes` impose separate limits on the use of
the pool. Allocating from the pool may fail if you try to
allocate more sets from it than `maxSets` _or_ more descriptors
than there is memory for according to `pPoolSizes`. What's worse,
a descriptor pool can become fragmented, so allocating from it
may fail anyway even if you're within these limits. We'll talk
about how to cope with all this in "Allocating descriptor sets".

[`VkDescriptorPoolCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPoolCreateInfo.html) also has a <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPoolCreateFlags.html">VkDescriptorPoolCreateFlags</a> flags</code> field with a couple flags of note:

* `VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT`: You can
  use
  [`vkFreeDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkFreeDescriptorSets.html)
  to free memory allocated from the pool for individual
  descriptor sets. Otherwise, your only option is to free all the
  memory in the pool at once with
  [`vkResetDescriptorPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkResetDescriptorPool.html)
  (which you can use whether or not you have this flag set).
* `VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT`: You can
  allocate sets from the pool that include bindings with
  `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` set (bindings
  without that flag set are fine either way).

Descriptor pools are destroyed with
[`vkDestroyDescriptorPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyDescriptorPool.html).
This automatically frees all the sets allocated from the pool, so
you don't need to free them beforehand.

#### Allocating descriptor sets

Descriptor sets are represented by
[`VkDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html)
handles. Rather than creating them directly, you allocate them
from descriptor pools with
[`vkAllocateDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateDescriptorSets.html),
which takes a <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html">VkDescriptorSet</a>\*
pDescriptorSets</code> array and accepts parameters in a
[`VkDescriptorSetAllocateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetAllocateInfo.html).

[`VkDescriptorSetAllocateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetAllocateInfo.html)
mainly exists for you to set the pool to allocate from and the
layout each descriptor set should be allocated with. It has
<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorPool.html">VkDescriptorPool</a>
descriptorPool</code> and <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayout.html">VkDescriptorSetLayout</a>\*
pSetLayouts</code> fields for this purpose.

The only other thing to note about
[`VkDescriptorSetAllocateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetAllocateInfo.html)
is that its `pNext` field can point to a
[`VkDescriptorSetVariableDescriptorCountAllocateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetVariableDescriptorCountAllocateInfo.html)
which can be used to set the descriptor counts for descriptors
with `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT`
bindings (see "Descriptor set layouts"). This is simple—it has a
`const uint32_t* pDescriptorCounts` array for the descriptor
counts, one entry for each corresponding member of
`pDescriptorSets` (members without
`VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` bindings
will be unaffected). Any descriptor sets that _do_ have
`VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` bindings
will have effective `descriptorCount`s of `0` if their counts are
not set here, so make sure to use this if you're making use of
that flag.

A call to
[`vkAllocateDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateDescriptorSets.html)
can fail with `VK_ERROR_OUT_OF_POOL_MEMORY` if any of the
allocations would exceed the limits implied by the pool's
`maxSets` or `pPoolSizes` attributes. It can also fail with
`VK_ERROR_FRAGMENTED_POOL` even if the allocations wouldn't
exceed these limits. If this occurs, all of the sets in the call
are invalid, so you'll have to try to allocate all of them again.
You can either free memory in the pool you were trying to use or
create a new pool to try with. A call to
[`vkAllocateDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkAllocateDescriptorSets.html)
can also fail with `VK_ERROR_OUT_OF_HOST_MEMORY` or
`VK_ERROR_OUT_OF_DEVICE_MEMORY`, in which case you'll probably
have to take more drastic measures.

If the allocation is successful, the descriptor sets are still
mostly uninitialized and their descriptors are undefined. You can
update them to initialize them; see "Updating descriptor sets"
for details. There are situations when you can bind and use
descriptor sets with undefined descriptors; see "Binding
descriptor sets" for the details on that.

To free memory in a descriptor pool, you can use
[`vkResetDescriptorPool()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkResetDescriptorPool.html),
which frees all the sets allocated from the pool and returns
their memory. If the pool was created with
`VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT` set (see
"Descriptor pools"), you can also use
[`vkFreeDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkFreeDescriptorSets.html)
to free only some of the memory allocated from the pool; it takes
an array of descriptor set handles indicating the sets to free.

#### Updating descriptor sets

Post-allocation, descriptor sets can be _updated_, which assigns
values to their descriptors. You can both write to them directly
and copy values into them from other descriptor sets.

##### [`vkUpdateDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkUpdateDescriptorSets.html)

One way to update them is with
[`vkUpdateDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkUpdateDescriptorSets.html).
You specify write and copy operations together with this
function. The write operations are described in an array of
[`VkWriteDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkWriteDescriptorSet.html)s,
and the copy operations are described in an array of
[`VkCopyDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCopyDescriptorSet.html)s.
The write operations are performed before the copy operations,
and the operations within each array are performed following
their order in their array.

###### [`VkWriteDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkWriteDescriptorSet.html)

[`VkWriteDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkWriteDescriptorSet.html)
is a bit complicated. You describe the location to write to in it
with these fields:

* <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html">VkDescriptorSet</a>
  dstSet</code>, which is the set to update,
* `uint32_t dstBinding`, which is the binding number to update
  within that set, and
* `uint32_t dstArrayElement`, which is the element to start with
  in the binding.

You can specify the actual data to write in one of these three
fields:

* <code>const <a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorImageInfo.html">VkDescriptorImageInfo</a>\*
  pImageInfo</code>, for images;
  [`VkDescriptorImageInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorImageInfo.html)
  has these fields:
    * <code><a
      href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSampler.html">VkSampler</a>
      sampler</code>, for `VK_DESCRIPTOR_TYPE_SAMPLER` and
      `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER` bindings that
      don't use immutable samplers (see "Descriptor set
      layouts"),
    * <code><a
      href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageView.html">VkImageView</a>
      imageView</code>, for `VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE`,
      `VK_DESCRIPTOR_TYPE_STORAGE_IMAGE` and
      `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`, and
      `VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT` bindings, and
    * <code><a
      href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkImageLayout.html">VkImageLayout</a>
      imageLayout</code>, the layout that the subresources
      accessible through `imageView` will be in when you access
      them through the descriptor (if you're using
      `imageView`)—you have to make sure that they're actually in
      this layout yourself;
* <code>const <a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorBufferInfo.html">VkDescriptorBufferInfo</a>\*
  pBufferInfo</code>, for buffers;
  [`VkDescriptorBufferInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorBufferInfo.html)
  has these fields:
    * <code><a
      href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBuffer.html">VkBuffer</a>
      buffer</code>, the buffer to write from,
    * <code><a
      href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceSize.html">VkDeviceSize</a>
      offset</code>, the offset into the buffer to use,
      and
    * <code><a
      href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceSize.html">VkDeviceSize</a>
      range</code>, how many bytes to write (can be
      `VK_WHOLE_SIZE`)—this should not exceed the maximum range
      for the descriptor type, either
      `VkPhysicalDeviceLimits::maxUniformBufferRange` or
      `VkPhysicalDeviceLimits::maxStorageBufferRange`;
* <code>const <a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBufferView.html">VkBufferView</a>\*
  pTexelBufferView</code>, for buffers views.

There are two other fields you have to set as well to specify the
data to write:

* <code><a
  href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorType.html">VkDescriptorType</a>
  descriptorType</code>, which should match the descriptor type
  for the binding you're writing to and which determines the
  array field that the data is written from, and
* `uint32_t descriptorCount`, the number of descriptors to
  update, which should match the number of elements in the array
  you're using to write from as indicated by `descriptorType`.

You can update multiple bindings in one go by using a
`descriptorCount` greater than the number of elements in
`dstBinding` starting at `dstArrayElement`. In this case, writing
will continue at the next binding starting at index `0`. All the
bindings written to this way must have the same descriptor type,
shader stage flags, binding flags, and immutable sampler
references (see "Descriptor set layouts").

###### [`VkCopyDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCopyDescriptorSet.html)

[`VkCopyDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkCopyDescriptorSet.html)
is simpler (thank goodness). It takes the location to write from
in <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html">VkDescriptorSet</a>
srcSet</code>, `uint32_t srcBinding`, and `uint32_t
srcArrayElement`, and the location to write to in <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSet.html">VkDescriptorSet</a>
dstSet</code>, `uint32_t dstBinding`, and `uint32_t
dstArrayElement`. The amount of data to copy is given in
`uint32_t descriptorCount`. These are all pretty
self-explanatory. `descriptorCount` can be used for updating more
than one binding in the same manner as in
[`VkWriteDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkWriteDescriptorSet.html).

##### Updating descriptor sets with templates

If you have a group of descriptors you use in several different
descriptor sets, specifying write operations for all of those
sets can involve a lot of redundant work for the driver if that
group of descriptors only really needs to be written to once.
_Descriptor update templates_ were added to the core in Vulkan
1.1 to help with this situation. A descriptor update template is
an object that describes a mapping from data in host memory to a
descriptor set. They're represented by
[`VkDescriptorUpdateTemplate`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplate.html)
handles and created with
[`vkCreateDescriptorUpdateTemplate()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateDescriptorUpdateTemplate.html),
which takes parameters in a
[`VkDescriptorUpdateTemplateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplateCreateInfo.html).

The main field in
[`VkDescriptorUpdateTemplateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplateCreateInfo.html)
is an array, <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplateEntry.html">VkDescriptorUpdateTemplateEntry</a>\*
pDescriptorUpdateEntries</code>. Each of these defines a
descriptor update operation. Similarly to the other structs for
updating descriptors, it has `uint32_t dstBinding`, `uint32_t
dstArrayElement`, `uint32_t descriptorCount`, and <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorType.html">VkDescriptorType</a>
descriptorType</code> fields for the binding number, starting
array element, number of descriptors to update, and descriptor
type respectively.  Like with
[`VkWriteDescriptorSet`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkWriteDescriptorSet.html),
`uint32_t descriptorCount` can be larger than the remaining array
elements in the current descriptor, with the same rules. However,
the remaining two fields in
[`VkDescriptorUpdateTemplateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplateCreateInfo.html)
are `size_t offset` and `size_t stride`.

These two fields specify a region of host memory. Notably, they
don't specify a _specific_ region of host memory—that comes later
when you call
[`vkUpdateDescriptorSetWithTemplate()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkUpdateDescriptorSetWithTemplate.html),
which takes a pointer. `size_t offset`, as you would expect, is
the distance in bytes from the pointer to the first block of
descriptor update information. `size_t stride` specifies the
distance between successive blocks of descriptor set update
information, also in bytes. The reason for `stride` is in case
you've stored the information in structs alongside other data.

[`VkDescriptorUpdateTemplateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplateCreateInfo.html)
also has a field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplateType.html">VkDescriptorUpdateTemplateType</a>
templateType</code>, but the only value it can take on in core
Vulkan is `VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET`. As
such, the other fields in
[`VkDescriptorUpdateTemplateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorUpdateTemplateCreateInfo.html)
are of no concern to us here.

Once you've created an update template, you can use it to update
descriptors with the aforementioned
[`vkUpdateDescriptorSetWithTemplate()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkUpdateDescriptorSetWithTemplate.html).
This is really easy—it just takes a descriptor set, an update
template, and a pointer to the location to start reading the
update information from.

When you're done with your update template, you can destroy it
with
[`vkDestroyDescriptorUpdateTemplate()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkDestroyDescriptorUpdateTemplate.html).

#### A brief glance at push constants

_Push constants_ are another way of getting data into shaders
aside from descriptors. Unlike descriptors, they don't wrap
memory-backed resources, so they are lighter-weight and thus more
performant than descriptors in many cases. They aren't
represented by a distinct object; instead, a pipeline layout
defines a set of _push constant ranges_, which specify an offset
and a size over some unformatted block of memory somewhere, and
of which only one can be available to a given shader stage. No
allocations or anything are performed at this time—the layout's
push constant ranges are purely descriptive. When a pipeline made
with the layout is bound to a command buffer, you can use a
command to write data to the memory described by the layout.
You declare the actual format of this data shader-side in an
interface block, at which point you can make use of it.

#### Pipeline layouts

Pipeline layouts represent a kind of blueprint for the resources
a pipeline will have available during execution. They're
represented by
[`VkPipelineLayout`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineLayout.html)
handles and created with
[`vkCreatePipelineLayout()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreatePipelineLayout.html).

[`vkCreatePipelineLayout()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreatePipelineLayout.html)
takes its parameters in a
[`VkPipelineCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineLayoutCreateInfo.html);
from examining this structure we can see that a pipeline layout
is basically an array of descriptor set layouts and an array of
push constant ranges. We already know what descriptor set layouts
are (see "Descriptor set layouts" if not), and we just touched on
push constant ranges a moment ago in "A brief glance at push
constants".

A pipeline layout's push constant ranges are each defined with a
[`VkPushConstantRange`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPushConstantRange.html).
This has a `uint32_t offset` and a `uint32_t size`, which are
specified in bytes and should be multiples of 4. Note that
`offset` must be less than
`VkPhysicalDeviceLimits::maxPushConstantsSize`, and that `size`
must be less than `VkPhysicalDeviceLimits::maxPushConstantsSize -
offset`. These limits are likely to be _very_ small—at the time
of writing, the two most common values for `maxPushConstantsSize`
are `128` and `256` by far, with a few recent macOS/iOS
environments supporting `4096` (see
[here](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxPushConstantsSize)).
`128` is the required minimum (see ["32.1 Limit
Requirements"](https://www.khronos.org/registry/vulkan/specs/1.1/html/vkspec.html#limits-minmax)
in the Vulkan spec).

In practice, the API treats push constants as occupying a single
block of memory `maxPushConstantsSize` bytes long. When you call
[`vkCmdPushConstants()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdPushConstants.html),
the `offset` and `size` parameters you specify are decoupled from
any of the `offset` and `size` parameters you set when creating a
pipeline layout. Each of these just specifies some part of push
constant memory. This allows you to give shader stages access
only to the push constants they actually need, and also to use
[`vkCmdPushConstants()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdPushConstants.html)
to update only the push constants that actually need it.

Push constants need to be laid out in memory in a certain way in
order for them to be read properly on the shader side. We'll talk
about this more when we discuss the `push_constant` layout
qualifier.

Speaking of shaders, the other field in
[`VkPushConstantRange`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPushConstantRange.html)
is <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkShaderStageFlags.html">VkShaderStageFlags</a>
stageFlags</code>, which describes the shader stages that will
have access to the push constant range. You can only expose one
push constant range to a given shader stage; Vulkan won't allow
you to set the same bit in `stageFlags` for two or more of the
push constant ranges in a given pipeline layout.

A pipeline layout is used in the creation of a pipeline to define
its descriptor and push constant interfaces. Pipeline layouts are
also used when binding descriptor sets and updating push
constants, in lieu of the actual bound pipeline object. This
level of indirection might seem a bit strange, but it does mean
that if you have multiple different pipelines which share the
same layout, you can use the same layout object for each. It also
means that if you bind a pipeline to a command buffer, then bind
a set of compatible descriptor sets, then bind a different
pipeline of the same type and with the same layout, the new
pipeline will be able to work with the previously-bound
descriptor sets.

#### Binding descriptor sets

[`vkCmdBindDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindDescriptorSets.html)
is meant to be recorded to a command buffer in conjunction with
[`vkCmdBindPipeline()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindPipeline.html).
The field <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineBindPoint.html">VkPipelineBindPoint</a>
pipelineBindPoint</code> in
[`vkCmdBindDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindDescriptorSets.html)
specifies the kind of pipeline that will use the descriptors; the
most recent pipeline of that kind which was bound to the same
command buffer with
[`vkCmdBindPipeline()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindPipeline.html)
will then have access to them. A pipeline supports a limited
number of bound descriptor sets, which are given by
`maxBoundDescriptorSets` in `VkPhysicalDeviceLimits` (most
commonly `32` on
[Windows](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxBoundDescriptorSets&platform=windows)
and
[Linux](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxBoundDescriptorSets&platform=linux)
as of June 2021).

Aside from a pipeline bind point,
[`vkCmdBindDescriptorSets()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindDescriptorSets.html)
also expects a pipeline layout which describes the descriptor
sets to be bound. Aside from this, it has `uint32_t firstSet` and
`uint32_t descriptorSetCount` fields defining the number of the
first set to bind to and the number of descriptors to bind
starting from there, as well as a corresponding array of
descriptor sets.

The other two fields are `uint32_t dynamicOffsetCount` and `const
uint32_t* pDynamicOffsets`. You only need to make use of these if
you're binding descriptors of type
`VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC` or
`VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC`. You might remember
our brief mention of these types back in "Descriptor set
layouts"; the idea with these is you can use `pDynamicOffsets`
here to specify offsets into the buffer at binding time.
`pDynamicOffsets` has one element for each array element in each
dynamic-type descriptor, arranged in the same order as they
appear in each descriptor and then by the order in which the
descriptors are numbered, with lower numbers coming first. This
is handy if you're using one large buffer to store a lot of
different data, as we explored back in "Memory mangement".

At the time that commands which involve the bound pipeline are
executed (draw commands for graphics pipelines, dispatch commands
for compute pipelines), you need to have bound all the
descriptors used by the shaders in the pipeline. Descriptors
_not_ used by the shaders don't need to be bound, though, even if
they're specified by the pipeline layout.

All the bound descriptor sets have to be _compatible_ with the
pipeline layout specified in the bind call. The layout itself
also has to be compatible with the bound pipeline when commands
that involve it are executed. "Compatible" means that the
descriptor set layouts and push constant ranges are defined the
same, number for number.

In ["Pipeline Layout
Compatability"](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#descriptorsets-compatibility),
the spec says something rather odd. It says,

> When binding a descriptor set (see [Descriptor Set
> Binding](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/vkspec.html#descriptorsets-binding))
> to set number N, if the previously bound descriptor sets for
> sets zero through N-1 were all bound using compatible pipeline
> layouts, then performing this binding does not _disturb_ any of
> the lower numbered sets. If, additionally, the previously bound
> descriptor set for set N was bound using a pipeline layout
> compatible for set N, then the bindings in sets numbered
> greater than N are also not _disturbed_.

(Emphasis mine.) The spec does not define what "disturbed" means
in this context, so it's hard to make heads or tails of this
paragraph. This issue has been [touched
on](https://github.com/KhronosGroup/Vulkan-Docs/issues/1485) in
the spec repo (albeit with regards to push constants, which are
also described this way), and the main point seems to be that as
long as you make sure that the most recent bound descriptors sets
covering the layout, push constants, and bound pipeline are all
compatible when you record your draw or dispatch commands, things
should be okay, basically.

#### Updating push constants

We talked about how to set up push constants in "Pipeline
layouts", but not actually how to assign values to them. The way
to do this is to use
[`vkCmdPushConstants()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdPushConstants.html).

This takes a pipeline layout describing the push constant ranges
and a bitmask of shader stage flags for the shader stages that
will access the push constants. It also takes an offset into the
push constant range to start the update at and a size of the
range to update, both in bytes. Aside from this, there's just a
`const void* pValues` field for an array that has the new push
constant values. Refreshing!

You can update push constant values in-between shader stages, and
the subsequent stages will see any new values you've set along
with the old values for push constants you haven't touched.

Of course, the layout used when updating the push constants must
be compatible with the layout of the bound pipeline when commands
that make use of it are issued, as with descriptor sets. The spec
says the same sorts of strange things about this—"Binding a
pipeline with a layout that is not compatible with the push
constant layout does not _disturb_ the push constant values"
(emphasis mine). See "Binding descriptor sets" above for more on
this.

#### Physical storage buffer access

This feature was promoted to Vulkan 1.2 from
[`VK_KHR_buffer_device_address`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VK_KHR_buffer_device_address.html).
Unfortunately, it still depends on support from the SPIR-V side,
and the necessary features are not in core SPIR-V at this time,
being enabled instead via
[`SPV_KHR_physical_storage_buffer`](https://htmlpreview.github.io/?https://github.com/KhronosGroup/SPIRV-Registry/blob/master/extensions/KHR/SPV_KHR_physical_storage_buffer.html).
It's potentially a very useful feature and I feel like I should
touch on it here since it's part of core Vulkan now, but in
practice you still can't count on universal support for it on the
shader side at this time. As such, I'm only going to briefly
mention what it's about and link to the relevant specs in case
you want to know more.

Basically, this feature exposes two functions,
<code><a href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceAddress.html">VkDeviceAddress</a> <a href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetBufferDeviceAddress.html">vkGetBufferDeviceAddress()</a></code>
and
<code>uint64\_t <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetBufferOpaqueCaptureAddress.html">vkGetBufferOpaqueCaptureAddress()</a></code>,
which can be used to get the address of a
[`VkBuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBuffer.html)
on the device. You can then store this address in e.g. a uniform
buffer, and in theory you could then read it from a shader and
use it as a pointer to the buffer's data. This could facilitate
lightweight and flexible interaction between the host and shader,
conceivably.

However, SPIR-V only supports this via an extension, as we just
discussed. Futhermore, as we have now learned, GLSL doesn't have
a built-in pointer type. There is an extension
[`GLSL_EXT_buffer_reference`](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GLSL_EXT_buffer_reference.txt)
that uses
[`SPV_KHR_physical_storage_buffer`](https://htmlpreview.github.io/?https://github.com/KhronosGroup/SPIRV-Registry/blob/master/extensions/KHR/SPV_KHR_physical_storage_buffer.html)
to support this feature, as well as two extensions that build on
it,
[`GLSL_EXT_buffer_reference2`](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GLSL_EXT_buffer_reference2.txt)
and
[`GLSL_EXT_buffer_reference_uvec2`](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GLSL_EXT_buffer_reference_uvec2.txt).
There is some discussion of all this in a [talk by one of the
spec
authors](https://www.youtube.com/watch?v=KLZsAJQBR5o&t=2493s)
(except
[`GLSL_EXT_buffer_reference2`](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GLSL_EXT_buffer_reference2.txt)
and
[`GLSL_EXT_buffer_reference_uvec2`](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GLSL_EXT_buffer_reference_uvec2.txt)).

### Qualifiers

Qualifiers are keywords used in declarations before the type name
that have some effect on how the subject of the declaration is or
can be handled. We've already encountered some of them, like
`lowp` and `inout`. However, we've delayed a comprehensive
discussion of them until now because they play a major role
in how your shader interfaces with the outside world. Since we've
laid the groundwork, we can now discuss them.

#### Storage qualifiers

When declaring a variable, a _single_ storage qualifier can be
specified before the type name, which can determine aspects of
the variable's mutability, linkage, and interpolation strategy.
There are also a few auxiliary storage qualifiers that can be
specified along with a storage qualifier.

As we've already discussed, if no qualifier is specified, the
variable is local to the shader and mutable. If `const` is
specified, the variable is local to the shader and immutable
after initialization. The rest of the storage qualifiers are new
to us.

##### Input and output variables (`in` and `out`)

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

Compute shaders don't support user-defined input or output
variables; they read from and write to images, storage buffers,
and atomic counters directly. That said, you specify the shader's
local workgroup size by applying the `local_size_x`/`y`/`z`
layout qualifers to `in` (see "In the compute shader" under
"Layout qualifiers").

##### Uniform variables (`uniform`)

Variables declared in a block can take the storage qualifier
`uniform` to indicate that they are initialized from the Vulkan
side. Such variables are read-only and will have the same value
across every invocation interacting with the same primitive.

`uniform` can be used with variables of basic or structure type,
or arrays of these types.

Since uniform variables all exist in a single global namespace at
link time, they need to be declared with the same name, type,
etc. in any shader that makes use of them.

##### Buffer variables (`buffer`)

The storage qualifier `buffer` indicates variables that are
accessed through a `VkBuffer` bound to the pipeline the shaders
are attached to. It must be used to qualify a block.

##### Shared variables (`shared`)

You can use the storage qualifier `shared` in compute shaders to
declare global variables that can be read from and written to by
all the shader invocations in a given local workgroup (see "In
the compute shader" under "Layout qualifiers" for more on local
workgroups). `shared` variables have a single representation in
memory per workgroup, and you have to take care to synchronize
reads and writes to them using `barrier()` in your compute shader
code.

You should declare shared variables without an initializer, so
that they're left undefined at the start of execution:

```glsl
shared vec4 alphas;
```

During execution, you can have an invocation write to a shared
variable and the results will be immediately visible to any of
the other invocations in its workgroup; shared variables are
implicitly coherent. However, shared variable access is not
implicitly synchronous, so you should use the function
`barrier()` between writing to and reading from shared variables
(see "`barrier()`" under "Invocation and memory control" below).

There is a limit to how much memory you can allocated for shared
variables on a given device. Vulkan specifies this limit in bytes
in `VkPhysicalDeviceLimits` under `maxComputeSharedMemorySize`.
As of May 2022, [common
values](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxComputeSharedMemorySize&platform=all)
for `maxComputeSharedMemorySize` are ~33kB and ~50kB, with some
outliers reporting ~16kB and ~66kB. For shared variables declared
in a uniform block, you can determine their layout in memory by
the rules in [15.6.4 "Offset and Stride
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
for `in` and `out` blocks (these qualifiers are collectively
known as _interface qualifiers_). Input and output blocks define
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
optional identifier `mats` after the block is called its
_instance name_, and if included the members are scoped into a
namespace under it. For instance, `mats[2].ndx` would be in scope
after this, but not plain `ndx`. However, if we had declared
`material` this way:

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

The compiler will throw an error if you declare an input block in
a vertex shader or an output block in a fragment shader. Regular
input or output variables are okay in these cases, though. If
this limitation strikes you as rather arbitrary, the GLSL spec
says ["These uses are reserved for future
use"](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#storage-qualifiers)
on this topic, so outside of long-term GLSL spec planning and
such you could be forgiven for feeling that way right now.

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

#### Layout qualifiers

Layout qualifiers are used in concert with interface qualifiers
(see "Interface blocks") to declare things about how the shader
receives and outputs data, such as the place the data comes from
or how it's represented in memory.

The layout qualifiers we cover here are those that can be used in
all shading stages. There are also some that only have use in a
specific stage; those are harder to understand without describing
the whole environment of that shader stage, so we'll go into them
in that context instead.

Layout qualifiers are declared with `layout`, `(`, one or more
layout qualifier phrases separated by commas, and `)`, in that
order. A layout qualifier phrase can consist of a layout
qualifier name by itself, or a layout qualifier name, ` = `, and
an constant integral expression, with optional spaces around the
`=`. For example:

```glsl
layout(triangle_strip, max_vertices = 60)
layout(stream=1)
```

You're allowed to use the same layout qualifier repeatedly in a
singe declaration, but the later uses of it will override the
earlier ones, so there's not much point.

To form a complete statement with a layout qualifier, you can
write it followed by an interface qualifier and a semicolon:

```glsl
layout(triangle_strip, max_vertices = 60) out;
```

This applies the layout qualifier to all of the variables
qualified with `out` in the shader.

You can also follow it up with a interface qualifier followed by
a variable declaration and a semicolon:

```glsl
layout(location = 4, component = 2) in vec2 a;
```

In this case, the layout qualifier is applied only to the
variable declared with it.

Last but not least, you can use a layout qualifier to qualify a
whole block:

```glsl
layout(location = 3) in struct S {
    vec3 a;
    mat2 b;
    vec4 c[2];
} s;
```

or a single block member:

```glsl
layout(column_major) uniform T3 {
    mat4 M3;
    layout(row_major) mat4 m4;
    mat3 N2;
};
```

The meaning of these sorts of constructions depends on the layout
qualifier.

Most layout qualifiers only support a subset of these kinds of
declarations. You can see a chart of what supports what in the
GLSL spec, section [4.4 Layout
Qualifiers](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#layout-qualifiers).

##### `std140` and `std430`

These qualifiers can only be applied to `uniform` and `buffer`
blocks, and dictate the memory layout of the block they're
applied to.  In practice, you probably won't use them much,
because

* `std140` is the default layout for `uniform` blocks,
* `std430` is the default layout for `buffer` blocks,
* you're not allowed to apply `std430` to `uniform` blocks, and
* you probably wouldn't want to apply `std140` to a `buffer`
  block because it's almost the same as `std430` but slightly
  more restrictive.

We should explore them anyway, though, so you understand how to
lay out data in your buffers for use in GLSL.

Both layouts are described in the [OpenGL
spec](https://www.khronos.org/registry/OpenGL/specs/gl/glspec46.core.pdf),
section "7.6.2.2 Standard Uniform Block Layout". You can look at
the spec for the fine details, but I figure I might as well sum
them up here just for your convenience. We'll talk about `std430`
first, because as I said it's almost the same as `std140` but
slightly more permissive.

The spec describes `std430` in terms of "basic machine units"
instead of a more concrete unit. I'm going to proceed in terms of
8-bit bytes—if you're working with a platform where that doesn't
hold, I feel confident you'll be able to account for the
difference.

Type                     | Alignment (B)
----------------------   | -------------
`bool`                   | size not specified; don't use
`int`, `uint`, `float`   |  4
`double`                 |  8
`vec2`, `ivec2`, `uvec2` |  8
`dvec2`                  | 16
`vec3`, `ivec3`, `uvec3` | 16
`dvec3`                  | 32
`vec4`, `ivec4`, `uvec4` | 16
`dvec4`                  | 32
array                    | same as one element
column-major matrix      | like a (columns)-sized array of (rows)-component vectors
row-major matrix         | like a (rows)-sized array of (columns)-component vectors
structure                | same as the member with the largest alignment value

Arrays and structures will have padding applied at the end if
needed to provide the correct alignment for the data following
them.

`std140` is exactly the same as `std430`, except that the
alignment of an array or structure is rounded up to a multiple of
16.

There is one exception to the rule that `uniform` blocks are laid
out acccording to `std140`—if the block has the layout qualifier
`push_constant`, it's laid out by `std430` instead, without
exception.

##### `align` and `offset`

These layout qualifiers can be used to get fine-grained control
over memory formatting in GLSL. `align` can be applied to
`uniform` and `buffer` blocks as well as their members, whereas
`offset` can only be applied to their members. Both take a
parameter in bytes.

`align` must be set to a power of 2. If applied to a block
member, it determines the minimum alignment of that member; if
applied to a block, it's as if the qualifier was applied to every
member of the block. Note that if the alignment is smaller than
dictated by the overall block layout as described in "`std430`
and `std140`", the alignment specified by the layout wins out.

`offset` must be set to a multiple of the base alignment for the
type of the block member as specified in "`std430` and `std140`".
It specifies the distance the block member will start from the
beginning of the buffer.

Say we have a buffer in Vulkan whose contents are equivalent to
those of the following array:

```cpp
int32_t buff[] = { 3, -6, 993, -129, 48, -231, 9, -402, 39, };
```

Now say in a shader we have the following block that's backed by
this buffer:

```glsl
uniform buff {
    int a;
    layout(offset = 20) int b;
    layout(align = 16) int c;
};
```

In this case, `a` would be `3`, `b` would be `-231`, and `c`
would be `39`.

If we had instead declared the block like this:

```glsl
layout(align = 16) uniform buff {
    int a;
    int b;
    int c;
};
```

then `a` would be `3`, `b` would be `48` and `c` would be `39`.

Both `align` and `offset` can be applied to a block member. In
this case, the specified offset is considered first; if it's not
a multiple of the specified alignment, the next position past the
specified offset that does fit the alignment is used.

For instance, if we had declared our block like this:

```glsl
layout(align = 8) uniform buff {
    layout(offset = 12) int a;
    int b;
    int c;
};
```

then `a` would be `48`, `b` would be `9`, and `c` would be `39`.

The compiler will stop you if you try to position a member such
that it would overlap with another, either explicitly or
implicitly:

```glsl
layout(align = 8) uniform buff {
    layout(offset = 12) int a;
    int b;
    layout(offset = 20) int c; // ERROR
};
```

As you've probably intuited, these qualifiers have no effect on
the internal layout of the member, which is still handled in
accordance with the block layout rules. They only adjust where
the member's data is located in the block as a whole.

##### `column_major` and `row_major`

These are for setting how matrices are laid out in memory. They
can be applied to `uniform` and `buffer` blocks as well as their
members, and can also be used to set the default for all
`uniform` or `buffer` blocks. If you don't set a default,
`column_major` will be the default for both.

```glsl
// now all matrices in `uniform` blocks are `row_major` by
// default for this shader
layout(row_major) uniform;

// but this block goes against the new default
layout(column_major) uniform col {
    // this matrix is `column_major`
    mat4x4 col_mat;
    // this matrix is `row_major`
    layout(row_major) row_mat;
    // this matrix is `column_major`
    mat4x4 col_mat_2;
    // this vector is unaffected either way
    vec4 oblivious;
};

// this block still has the default setting
buffer also_col {
    // this matrix is `column_major`
    mat4x4 col_mat_also;
}
```

As you can see, both qualifiers only affect matrices, and each
only overrides its counterpart.

As described in "`std430` and `std140`", `column_major` means
that if the matrix has _m_ columns and _n_ rows, it's laid out in
memory like an _m_-sized array of _n_-sized vectors, with
`row_major` being the other way around.

Let's consider an example. Say we have the following matrix:

```
/ 9 6 2 4 \
\ 1 0 3 5 /
```

Since memory is one-dimensional from the perspective of C or C++
as well as conventional computer hardware, we wouldn't be able to
lay this out in memory exactly as we would write it in
mathematical notation. The two major conventions are like this:

```cpp
int col_maj[] = { 9, 1, 6, 0, 2, 3, 4, 5, };
int row_maj[] = { 9, 6, 2, 4, 1, 0, 3, 5, };
```

As you can see, in `col_maj` the values are stored going first
from the top down and then from left-to-right, whereas in
`row_maj` they're stored going left-to-right first and then
from the top down.

If we had a buffer with the data from `col_maj` followed
immediately by the data from `row_maj`, we might access it in
GLSL like this:

```glsl
uniform mats {
    mat4x2 col_maj;
    layout(row_major) mat4x2 row_maj;
}
```

Note that after this point both matrices would appear identical
in GLSL:

```glsl
vec2 first_col = { 9, 1 };
col_maj[0] == first_col; // true
row_maj[0] == first_col; // true
```

GLSL always thinks of matrices in column-major terms, aside from
cases of memory layout.

##### `location` and `component`

These layout qualifiers can be used in any kind of shader aside
from compute shaders, as they're paired with `in` and `out`
storage qualifiers. That said, they play a special role in the
vertex shader input interface and the fragment shader output
interface, where they define things like how the vertex shader
receives vertex data or where the fragment shader outputs color
data. In the other shading stages, they're just used to pass data
in from earlier stages and out to later ones.

You have to provide `location` qualifiers either explicitly or
implicitly for all the inputs and outputs you declare yourself
(i.e. those that aren't built-in).

`location` can be used with variable declarations, block
declarations, and block member declarations.  `component` should
be paired with `location` if used, and can only be used with
input variable and input block member declarations (not whole
blocks). Both of them should be declared with a constant integral
expression, like so:

```glsl
const int starting_loc = 3;
layout(location = starting_loc + 2, component = 2) out vec2 a;
```

`location` connotes the start of a 128-bit shader interface slot.
As such, to have a variable cover a space within a single
`location` slot, it should be of 16-, 32-, or 64-bit scalar or
vector type; if 64-bit, only 2-component vectors will do. For
instance:

```glsl
layout(location = 1) in vec4   span;      // spans the whole slot
layout(location = 1) in dvec2  d_span;    // also spans the whole slot
layout(location = 1) in vec2   fst_half;  // fst_half.xy == span.xy
layout(location = 1) in float  fst_com;   // fst_com     == span.x
layout(location = 1) in double fst_d_com; // fst_d_com   == d_span.x
```

(Note that in practice two different variables aren't allowed to
share a location qualifier, so this wouldn't compile—it's just
for show.)

Of course, you might want to cover a part of the slot that
doesn't start at the beginning. This is where `component` comes
in; it basically specifies an offset in multiples of 32 bits:

```glsl
layout(location = 1, component = 0) in float  fst_com_2; // fst_com_2   == fst_com
layout(location = 1, component = 1) in float  snd_com;   // snd_com     == span.y
layout(location = 1, component = 2) in double snd_d_com; // snd_d_com   == d_span.y
layout(location = 1, component = 2) in vec2   snd_half;  // snd_half.xy == span.za
```

Be mindful of alignment when using `component`—this is easy
overall since GLSL mostly has 32-bit types, but the compiler will
turn up its nose if you try to start a `double` at component `1`:

```glsl
layout(location = 0, component = 1) in double broken; // ERROR
```

You might be wondering what happens if you use `location` with a
variable that spans more than 128 bits. In this case, the span of
memory covered by the variable overlaps the next locations:

```glsl
layout(location = 2) in vec4 v_a;
layout(location = 3) in vec4 v_b;

layout(location = 2) in mat4x2 m;     //  m[0] == v_a;  m[1] == v_b
layout(location = 2) in vec4   vs[2]; // vs[0] == v_a; vs[1] == v_b

layout(location = 4) in dvec2 d_v_a;
layout(location = 5) in dvec2 d_v_b;

layout(location = 4) in dvec4 d_v_ab; // d_v_ab.xy == d_v_a; d_v_ab.za == d_v_b
```

This even works with a block or structure:

```glsl
layout(location = 2) in vs_blk {
    vec4 blk_a;
    vec4 blk_b;
};

// blk_a == v_a
// blk_b == v_b

layout(location = 2) in struct vs_strc {
    vec4 a;
    vec4 b;
} vs_strc_s;

// vs_strc_s.a == v_a
// vs_strc_s.b == v_b
```

You should note that types which take up less than 128 bits still
consume a whole location if used in a block or structure:

```glsl
layout(location = 1) vec2 v_a_64;
layout(location = 2) vec2 v_b_64;

layout(location = 1) in vs_blk_64 {
    vec2 blk_a_64; // blk_a_64 == v_a_64
    vec2 blk_b_64; // blk_b_64 == v_b_64
};
```

Struct members are not allowed to have their own location
qualifiers. However, block members can; if we wanted to get
around the above rule, we could do the following:

```glsl
layout(location = 1) vec4 v_a_128;

layout(location = 1) in vs_blk_64 {
    vec2 blk_a_64;                                     // blk_a_64 == v_a_128.xy
    layout(location = 1, component = 1) vec2 blk_b_64; // blk_b_64 == v_a_128.za
};
```

If you declare a block with a location qualifier, its members
take their locations in order following it until one of the
members has its own location qualifier. After that, the next
members take their locations following from _that_ location:

```glsl
layout(location = 1) in ivec4 v_a;
layout(location = 2) in ivec4 v_b;
layout(location = 3) in ivec4 v_c;
layout(location = 4) in ivec4 v_d;

layout(location = 1) in int_blk {
    int n_x;                                     // n_x == v_a.x
    layout(location = 3, component = 1) int p_y; // p_y == v_c.y
    int q_x;                                     // q_x == v_d.x
    layout(location = 2) int o_z;                // o_z == v_b.z
    int p_x;                                     // p_x == v_b.x
}
```

As you can see, the block member location qualifiers don't need
to come in a particular order, either.

You might also be wondering if variables declared with
`component` can overlap the next location. For the most part,
they cannot:

```glsl
layout(location = 2, component = 3) in dvec2 broken; // ERROR
```

By the same token, matrices, blocks, and structures cannot be
qualified with `component`. There is one exeception,
though—arrays declared with a component qualifier get their
elements from the specified component of each successive location
over their length:

```glsl
layout(location = 0) in vec4 v_a;
layout(location = 1) in vec4 v_b;
layout(location = 2) in vec4 v_c;
layout(location = 3) in vec4 v_d;

layout(location = 0, component = 3) in zs[4];

/**
 * zs[0] == v_a.z
 * zs[1] == v_b.z
 * zs[2] == v_c.z
 * zs[3] == v_d.z
 */
```

If the array contains a matrix, structure, or block, though, it
can't take `component`.

You should also be careful not to accidentally assign the same
location and component to two different variables in a block;
this is in error, as we discussed earlier:

```glsl
layout(location = 1) out broken_blk {
    vec4 v;
    layout(location = 1) vec4 v_again; // ERROR
}
```

As a reminder on this basis, most of the above examples would not
actually compile as a result of location and component aliasing.
It's just easier to show things this way.

There is a limit on the number of input and output locations
supported for each shader stage. You can see what they are in
[Table 11. Shader Input and Output
Locations](https://www.khronos.org/registry/vulkan/specs/1.0/html/chap15.html#interfaces-iointerfaces-limits)
in the Vulkan spec.

###### In the vertex shader

`location` and `component` are used in the vertex shader to
declare input variables that receive _vertex attribute_ data via
_vertex input bindings_ established during pipeline creation and
associated with buffers via a command. In plainer language, this
is how vertex shaders receive information like vertex position
and other sorts of per-vertex data.

Let's say you've got a vertex shader with the following
interface block:

```glsl
layout(location = 0) in vert {
    vec4 pos;
    vec3 color;
    layout(location = 1, component = 3) float alpha;
};
```

and you have the following structs declared in C++:

```cpp
struct Position {
    std::array<float, 4> pos;
};

struct Color {
    std::array<float, 4> rgba;
};

struct Vertex {
    Position pos;
    Color col;
};
```

(In practice you'd probably use types from a linear algebra
library here, but let's keep this simple.)

Now let's say you've got a `VkBuffer verts` whose members are
instances of `Vertex`, one for each vertex shader invocation.
You'd like to make draw calls using this buffer.

When you're creating your graphics pipeline, take note of the
<code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html">VkPipelineVertexInputStateCreateInfo</a>\*
pVertexInputState</code> array field in
[`VkGraphicsPipelineCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkGraphicsPipelineCreateInfo.html).
[`VkPipelineVertexInputStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html)
specifies two arrays, <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputBindingDescription.html">VkVertexInputBindingDescription\*</a>
pVertexBindingDescriptions</code> and <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputAttributeDescription.html">VkVertexInputAttributeDescription\*</a>
pVertexAttributeDescriptions</code>.

[`VkVertexInputBindingDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html)
is the coarser of the two. This has fields `uint32_t binding` and
`uint32_t stride`. `binding` is the vertex input binding number
and can be whatever you like; it has no direct bearing on your
vertex shader. `stride` gives the distance between two elements
in the buffer that will be bound for this buffer. (There's also
an `inputRate` field, but we'll come back to that in a bit.) For
our `VkBuffer verts`, we might declare the following:

```cpp
constexpr uint32_t vert_bind_n = 0;

VkVertexInputBindingDescription vert_desc {
    .binding   = vert_bind_n,
    .stride    = sizeof(Vertex),
    .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
};
```

[`VkVertexInputAttributeDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html)
is where you actually set up the shader interface. It has a
`uint32_t binding` field that corresponds to
[`VkVertexInputBindingDescription::binding`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html),
and a `uint32_t offset` field that describes an offset in bytes
for the attribute relative to the start of an element in the
input binding. It also has a `uint32_t location` field for the
number of the location in the shader, and a <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormat.html">VkFormat</a>
format</code>
field for the format of the attrbute data. Since we have two
locations, we'll need two of these:

```cpp
VkVertexInputAttributeDescription pos_desc {
    .location = 0,
    .binding  = vert_bind_n,
    .format   = VK_FORMAT_R32G32B32A32_SFLOAT,
    .offset   = 0,
};

VkVertexInputAttributeDescription col_desc {
    .location = 1,
    .binding  = vert_bind_n,
    .format   = VK_FORMAT_R32G32B32A32_SFLOAT,
    .offset   = sizeof(Position),
};
```

(You can use
[SPIRV-Reflect](https://github.com/KhronosGroup/SPIRV-Reflect) to
avoid duplicating the location numbers between your vertex
attribute descriptions and vertex shaders.)

Note that `format` has to be set to a format with
`VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT` set in its
[`VkFormatProperties::bufferFeatures`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormatProperties.html)
after calling
[`vkGetPhysicalDeviceFormatProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceFormatProperties.html)
for it. Fortunately, many formats have mandatory support for use
with vertex buffers; you can see which under
[43.3. Required Format Support](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/html/chap43.html#features-required-format-support) in the Vulkan spec.

Now we can set up our
[`VkPipelineVertexInputStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html):

```cpp
std::vector<VkVertexInputBindingDescription> bind_descs { vert_desc };

std::vector<VkVertexInputAttributeDescription> attr_descs {
    pos_desc,
    col_desc,
};

VkPipelineVertexInputStateCreateInfo vert_input_inf {
    .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    .pNext = nullptr,
    .flags = 0,
    .vertexBindingDescriptionCount   = bind_descs.size(),
    .pVertexBindingDescriptions      = bind_descs.data(),
    .vertexAttributeDescriptionCount = attr_descs.size(),
    .pVertexAttributeDescriptions    = attr_descs.data(),
}
```

Now let's say we've made a graphics pipeline using
`vert_input_inf` and we've bound it to a command buffer. To make
our data in `VkBuffer verts` available to its vertex shader, we
can use
[`vkCmdBindVertexBuffers()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindVertexBuffers.html).

This command can be used to attach a set of buffers to a set of
vertex input bindings in a relatively arbitrary manner. It has
`uint32_t firstBinding` and `uint32_t bindingCount` fields
denoting the number of the binding to start with and how many
bindings to set up from that number on. It also has array fields
<code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBuffer.html">VkBuffer</a>\*
pBuffers</code>
and <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceSize.html">VkDeviceSize</a>\*
pOffsets</code>, which both have one element per `bindingCount`.
The elements of `pOffsets` give offsets into the corresponding
elements of `pBuffers` for where the data for the binding starts.

We've only got one buffer and one binding, so this will be
straightforward:

```cpp
std::vector<VkBuffer>     vert_buffs        { verts };
std::vector<VkDeviceSize> vert_buff_offsets { 0 };

vkCmdBindVertexBuffers(cmd_buff, // to which we've bound our graphics pipeline
                       vert_bind_n,
                       vert_buffs.size(),
                       vert_buffs.data(),
                       vert_buff_offsets.data());

```

Now any subsequent draw command executions from this command
buffer will pass the data in `verts` to the vertex shading stage
of our bound graphics pipeline. (In practice, you can also bind
the vertex buffers first, as long as both the vertex buffers and
the pipeline are bound when you record the first draw command.)

(As a side note, in a real application, I lightly encourage you
to use a more sophisticated code design than these examples show;
some well-written classes would make this code much easier to
understand and maintain in a more complicated setting.)

One last point. Remember how we set `VK_VERTEX_INPUT_RATE_VERTEX`
for
[`VkVertexInputBindingDescription::inputRate`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputBindingDescription.html)?
There's actually one other possible value for that field,
`VK_VERTEX_INPUT_RATE_INSTANCE`. This means that the vertex input
binding will index into its buffer based on the _instance index_
instead of the vertex index.

The instance index comes from the parameters `uint32_t
instanceCount` and `uint32_t firstInstance` in draw commands like
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html).
If you set `instanceCount` to a value greater than one, the draw
command will loop over the specified vertex indices
`instanceCount` times. The instance index will start at
`firstInstance` and be incremented for each loop. In GLSL, you
can get the current value of the instance index from the vertex
shader using the built-in variable `gl_instanceIndex`.

So, `VK_VERTEX_INPUT_RATE_INSTANCE` can be used to pass data to
the vertex shader by instance instead of by vertex. This can be
used to perform _instanced rendering_ (also known as
_instancing_). Instanced rendering is a technique where the same
mesh is rendered in many different places in the scene
efficiently; it's commonly used for things like grass where the
mesh has only a few vertices but needs to be rendered over and
over.

To do this, you can have a vertex input binding with a
`VK_VERTEX_INPUT_RATE_INSTANCE` input rate and tie it to a buffer
with position and rotation information for each instance of the
mesh you want to render. Then you can set `instanceCount` in your
draw command to however many elements you have in your
position+rotation buffer. If you pull your position information
from that input binding in your vertex shader, the rest will take
care of itself.

Of course, there are lots of other things you can do with this
feature—any time you have a set of vertex data you want to render
repeatedly and have something change on each iteration, this may
come in handy. In some cases you can also do without a
`VK_VERTEX_INPUT_RATE_INSTANCE` binding and just use
`gl_instanceIndex`, like if you want to compute the varying data
procedurally in the vertex shader.

###### In the tessellation control, tessellation evaluation, and geometry shader

Input variables qualified with `location` in these shaders are
part of their interfaces with other shading stages, so the rules
around them are not as involved as with vertex and fragment
shaders. The available locations for inputs in a certain stage
match those of the outputs of the previous stage. One thing to be
mindful of is that, as we discussed in "Storage qualifiers",
non-`patch` inputs for all three as well as non-`patch`
tessellation control outputs are always arrays.  However, when
considering how many locations one of these variables consumes in
one of these shaders, you should disregard the outer level of
arrayness:

```glsl
// in the vertex shader

layout(location = 3) out vec4 v;
```

```glsl
// in the tessellation control shader

// only consumes location 3 regardless of vs's length
layout(location = 3) in vec4 vs[];
```

###### In the fragment shader

The available locations for inputs in the fragment shader match
the outputs of the previous stage. However, the outputs of the
fragment shader are special. Its available output locations match
the color attachments of the current subpass, as I mentioned
offhand back in "Subpass descriptions".

You might recall from that section that `VkSubpassDescription`
has an array field <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkAttachmentReference.html">VkAttachmentReference</a>\*
pColorAttachments</code>. You might also recall that attachments
are essentially image views from the point of view of the render
pass. Each output location available in the fragment shader
corresponds to a texel of one of the elements of
`pColorAttachments[]` at the corresponding index—`layout(location
= 0) in vec4 tex` corresponds to a texel of
`pColorAttachments[0]` and so on.

My choice of `vec4` for `tex` was not arbitrary—you can use other
types, but `vec4` is fairly natural because each of the four
components of one of these locations corresponds to the R, G, B,
and A values for the texel in question (`uvec4` or the like might
make more sense if the image has an integer format, of course).

If you do split one of these outputs up by component, note that
the different variables need to have the same type:

```glsl
location(layout = 0, component = 1) out float b;
location(layout = 0, component = 2) out int   g; // ERROR
```

Technically, you aren't writing directly to the underlying image
with these, but rather passing input to the _blend equation_.
We'll talk about this more when we discuss `index` and when we
cover blending.

###### In the compute shader

Although compute shaders have no user-defined inputs or outputs,
they still require you to use a family of input layout qualifiers
to specify the shader's _local workgroup size_: `local_size_x`,
`local_size_y`, and `local_size_z`. To use them, you can just
specify them for the `in` interface qualifier, without specifying
any particular input variable.

By default, all three are set to `1`, so if you wrote

```glsl
layout(local_size_x = 4, local_size_y = 4) in;
```

at the top of a compute shader, you would be specifying a
two-dimensional compute shader with a 4 × 4 workgroup size.

If you create a program object that includes any compute shaders,
you have to use these layout qualifiers to specify a fixed
workgroup size in at least one of them. If you include several
compute shaders in a single program object and you use these
layout qualifiers in more than one of them, you have to write the
same declaration with them in every compute shader in the program
object.

Compute shader invocations running within the same local
workgroup can share data between one another and synchronize
their work (.

##### `set` and `binding`

Whereas `location` and `component` go with `in` and `out`, `set`
and `binding` go with `uniform` and `buffer`. This is the shader
side of the descriptor interface we discussed from the Vulkan
perspective in "Resource descriptors". As you might imagine,
`set` corresponds to an index into
[`VkDescriptorSetLayoutCreateInfo::pBindings`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutCreateInfo.html),
and `binding` corresponds to the
[`VkDescriptorSetLayoutBinding::binding`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html)
within the descriptor set specified by `set`. A binding can be
accessed from any shader stage specified in its
[`VkDescriptorSetLayoutBinding::stageFlags`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html).

If the binding is an array (i.e. if it has a
[`VkDescriptorSetLayoutBinding::descriptorCount`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDescriptorSetLayoutBinding.html)
greater than `1`), you can declare it as an array in the shader
as well:

```glsl
layout(set = 2, binding = 3) uniform sampler2D samps[5];
```

If you don't declare it as an array, you'll implicitly be
accessing the first element of the binding:

```glsl
// fst_samp == samps[0] above
layout(set = 2, binding = 3) uniform sampler2D fst_samp;
```

Similarly, any declaration with `uniform` or `buffer` that omits
`set` or `binding` is equivalent to the same declaration with a
`set` or `binding` of `0`.

You might remember back in "Descriptor set layouts" how I
suggested we wait until we'd gone over qualiiers to talk about
the different descriptor set types. Hold that thought—we've still
got a ways to go until we can fully cover how to interact with
descriptors in GLSL.

##### `push_constant`

This layout qualifier is what you use to access push constants,
unsurprisingly. You have to apply it to a `uniform` block, and
there can only be one such block per shader stage. You can give
it an instance name if you want:

```glsl
layout(push_constant) uniform push_cs {
    int   meow;
    float cow;
} my_lovely_push_cs_inst_name;
```

As you might recall from "Pipeline layouts", you can only supply
one push constant range to a given shader stage when creating a
pipeline layout, so whichever range you specified for the shader
stage in question is the one you'll access. If the current stage
has no push constant range specified in its pipeline, you'll get
undefined values for the variables in this block, so watch out!
Similarly, it's up to you to make sure that the variables you
declare in the block properly cover the push constant range—if
you go past the end of it you'll also get undefined values after
that. Push constants are rather dangerous; at least they're
read-only.

If you've read the previous section "`std140` and `std430`",
you'll know that `push_constant` blocks are laid out according to
`std430`. If you haven't read that section, you can take a gander
at it to learn about how GLSL expects the contents of the buffer
backing a `push_constant` block to be laid out. You might
remember that a push constant range in a pipeline layout is only
described by a size and offset (see "Pipeline layouts"); it's
here in GLSL that we actually describe the format of its data.

Let's consider an example. We'll use the following class:

```cpp
template<typename Data>
class PushConsts {
public:
    static constexpr uint32_t max_size = 128;

    static constexpr uint32_t size()
    {
        constexpr std::size_t data_size = sizeof(Data);

        static_assert(data_size <= max_size,
                      "Your push constant data is too large for some "
                      "environments");

        return static_cast<uint32_t>(data_size);
    }

    PushConsts(Data d)
        :dat{std::make_unique<Data>(d)}
    {}

    PushConsts(const PushConsts&) =delete;
    PushConsts& operator=(PushConsts) =delete;

    PushConsts(PushConsts&&) =default;
    PushConsts& operator=(PushConsts&&) =default;

    ~PushConsts() =default;

    Data* data() { return dat.get(); }

private:
    std::unique_ptr<Data> dat;
};
```

Say we want to send a view matrix and a constantly-shfting wacky
background color to our shaders as push constants. The view
matrix will be a standard `mat4x4`. Just to make things a bit
spicy, let's say that we need to maintain really high precision
around the background color for some reason, to the point that we
want to send it in a `dvec3`.

We can see from the chart in "`std140` and `std430`" that a
`dvec3` needs to be aligned on a 32-byte boundary. The chart also
tells us that a `mat4x4` is the same as a `vec4[4]` for alignment
purposes, meaning it needs to be aligned on a 16-byte boundary.
However, the matrix will take up more space—64 bytes, to be
exact. A `dvec3` is smaller, at 24 bytes.

This implies that the most efficient arrangement of our data is
to put the matrix first and the vector afterwards. We need 64 +
24 = 88 bytes of space with this scheme, which is within the
minimum `maxPushConstantsSize` of 128 bytes:

```cpp
struct PushConstsData {
    std::array<float, 16> view_mat;
    std::array<double, 3> backg_col;
};

PushConsts<PushConstsData> push_cs {
    {
        .view_mat  = { /* components */ },
        .backg_col = { /* components */ },
    },
};
```

When we're ready, we can initialize our push constants like this:

```cpp
vkCmdPushConstants(cmd_buff,
                   pipe_layout,
                   VK_SHADER_STAGE_VERTEX_BIT
                   | VK_SHADER_STAGE_FRAGMENT_BIT, // or w/e
                   0,
                   push_cs.size(),
                   push_cs.data());
```

Then in our shaders, we can declare the following:

```glsl
layout(push_constant) uniform push_cs {
    mat4x4 view;
    dvec3  backg_col;
};
```

Now, perhaps the fragment shader doesn't really need access to
the view matrix, and the vertex shader doesn't really need access
to the background color. We might choose to do this instead:

```glsl
// vertex

layout(push_constant) uniform vert_push_cs {
    mat4x4 view;
};
```

```glsl
// fragment

layout(push_constant) uniform frag_push_cs {
    layout(offset = 64) dvec3 backg_col;
};
```

When creating our pipeline layout, we might then use the
following push constant ranges:

```cpp
const auto vert_push_size = sizeof(push_cs.data()->view_mat);
const auto frag_push_size = sizeof(push_cs.data()->backg_col);

VkPushConstantRange vert_range {
    .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
    .offset     = 0,
    .size       = vert_push_size,
};

VkPushConstantRange frag_range {
    .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
    .offset     = vert_push_size,
    .size       = frag_push_size,
};
```

With this approach, it is actually necessary to specify an offset
here both in the fragment shader and in the push constant range
for the fragment shader. Otherwise, `backg_col` in `frag_push_cs`
will come from the beginning of push constant memory and thus
what its value will be is undefined, since we specified an offset
past that point in `frag_range`. You also need to make sure to
give your `push_constant` blocks different names or the compiler
won't like it (an interface block with the same name must have
the same definition across linked shaders).

Now, I hope you'll forgive me if I get on a soapbox for just a
moment. In my opinion, the extra complexity involved in
coordinating the offsets for different shading stages between
pipeline layouts and shader code just ain't worth it in most
cases. Keeping the format of push constant memory straight
between Vulkan and your shaders is bad enough in general without
the extra bug surface introduced by managing different ranges of
it for each shading stage. If you find that your application's
performance is limited by whether or not you write or read 8
bytes vs. 64 bytes of push constant memory per frame or what have
you, go ahead and fuss about these details, but otherwise I would
recommend starting from the beginning of push constant memory
every time you call `vkCmdPushConstants()`. Your code will be
much simpler and less likely to have baffling problems, and with
a little planning you won't have to specify any offsets at all.

If you can fit all the data you need for a frame in push constant
memory at once, you can even write out the definition of the
`push_constant` block in a separate file and copy it into the
relevant shader source files as part of your build process so you
don't have to duplicate its definition. Then you can call
`vkCmdPushConstants()` once per frame with that frame's data and
not have to worry about it after that. Otherwise, I would write
all the data you need from the start of the range before each
relevant shading stage.

For instance, let's say that we want two `mat4x4`s in push
constant memory for our vertex shader, but we still want to have
that background color available in our fragment shader. Two
`mat4x4`s will take up all of the available 128 bytes. We can do
this:

```glsl
// vertex

layout(push_constant) uniform vert_push_cs {
    mat4x4 view;
    mat4x4 other;
};
```

```glsl
// fragment

layout(push_constant) uniform frag_push_cs {
    dvec3 backg_col;
};
```

We can also make the following modifications to our `PushConsts`
class:

```cpp
template<typename Data>
class PushConsts {
public:
    // ...

    static constexpr uint32_t offset = 0;

    PushConsts(Data d, VkShaderStageFlags s)
        :dat{std::make_unique<Data>(d)},
         stgs{s}
    {}

    // ...

    VkShaderStageFlags stages() const { return stgs; }

    VkPushConstantRange range() const
    {
        return {
            .stageFlags = stages(),
            .offset     = offset,
            .size       = size(),
        };
    }

    void push(VkCommandBuffer buff, VkPipelineLayout pipel) const
    {
        vkCmdPushConstants(buff, pipel, stages(), offset, size(), data());
    }

private:
    // ...
    VkShaderStageFlags stgs;
};
```

We can set up our push constant objects and push constant ranges
as follows:

```cpp
struct VertPushCData {
    std::array<float, 16> view_mat;
    std::array<float, 16> other_mat;
};

struct FragPushCData {
    std::array<double, 3> backg_col;
}

PushConsts<VertPushCData> vert_push_cs {
    {
        .view_mat  = { /* components */ },
        .other_mat = { /* components */ },
    },
    VK_SHADER_STAGE_VERTEX_BIT,
};

PushConsts<FragPushCData> frag_push_cs {
    {
        .backg_col = { /* components */ },
    },
    VK_SHADER_STAGE_FRAGMENT_BIT,
};

std::vector<VkPushConstantRange> push_c_rngs {
    vert_push_cs.range(),
    frag_push_cs.range(),
};
```

Then we can set up the following subpass dependency during render
pass creation:

```cpp
VkSubpassDependency vert_frag_push_cs_dep {
    .srcSubpass   = vert_subp_ndx, // i.e. 0
    .dstSubpass   = frag_subp_ndx, // i.e. 1
    .srcStageMask = VK_PIPELINE_STAGE_NONE_KHR,
    .dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
    // ...
};
```

Finally we can proceed as follows when recording commands in the
render pass:

```cpp
// ...
vert_push_cs.push(cmd_buff, pipe_lay);
vkCmdBeginRenderPass(/* ... */);
// ...
frag_push_cs.push(cmd_buff, pipe_lay);
vkCmdNextSubpass(/* ... */); // start subpass at frag_subp_ndx
// ...
```

Of course, depending on the circumstances, it might make more
sense to store some of this data in a regular uniform buffer
somewhere and save ourselves the synchronization hassle. You'll
have to test and see what's faster and/or easier to work with and
then make your own decisions.

##### `constant_id`

This qualifier is used to access _specialization constants_ from
GLSL, which are constants set from the Vulkan side during
pipeline creation. They're associated with a specific shader
stage. The Vulkan spec
[implies](https://www.khronos.org/registry/vulkan/specs/1.1-khr-extensions/html/chap10.html#pipelines-specialization-constants)
that their intended purpose is for runtime shader configuration;
their usage examples are supplying platform-specific information
to a shader and setting the local workgroup size of a compute
shader.

Specialization constants have some advantages over uniform
buffers because their values can be known at compile time. Nvidia
[recommends](https://developer.nvidia.com/blog/vulkan-dos-donts/)
the use of specialization constants (see "Pipelines" in that
article) and notes that they may improve shader efficiency (at
least on their hardware, of course). They also point out that you
can use them over shader variants to cut down on the amount of
shader bytecode you have to ship. Arm [also recommends their
use](https://arm-software.github.io/vulkan_best_practice_for_mobile_developers/samples/performance/specialization_constants/specialization_constants_tutorial.html)
for similar reasons; they note that their driver may remove
unused code blocks and unroll loops if specialization constant
state allows for this, and even go so far as to recommend that
specialization constants be used for "all control flow" on this
basis.

The
[`VkPipelineShaderStageCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineShaderStageCreateInfo.html)
structure used to supply the shader code for a shader stage is
also where you set values for specialization constants; it has an
optional parameter <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSpecializationInfo.html">VkSpecializationInfo</a>\*
pSpecializationInfo</code>, which if used should point to a
single
[`VkSpecializationInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSpecializationInfo.html).
This struct has a parameter `const void* pData` where you can
pass the actual values for the specialization constants. Of
course, since you pass a `void*`, Vulkan needs some way to know
what you're handing it, which is why there's also a <code>const
<a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSpecializationMapEntry.html">VkSpecializationMapEntry</a>\*
pMapEntries</code> array parameter.

[`VkSpecializationMapEntry`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkSpecializationMapEntry.html)
has `uint32_t offset` and `size_t size` parameters that bound a
specialization constant value in the memory pointed to by
`pData`. Its other parameter is `uint32_t constantID`. You can
set this to whatever `uint32_t` you like, which you can then use
to access the constant in GLSL.

Here's an example class for storing specialization constant state
in C++. It's perhaps mildly spooky as it internally employs
`reinterpret_cast` and a `std::byte` pointer, but alas, such
indiscretions can be hard to avoid when working with C APIs
(Vulkan expects a `void*` to your data anyhow). By grinding
everything into raw bits regardless of type, this also gives you
the freedom to add whatever you'd like to the set of
specialization constants; if you do anything wacky with this
approach make sure you understand how your data will appear on
the GLSL side. Note that in general Vulkan expects data in host
endianness, e.g. when [receiving SPIR-V
modules](https://www.khronos.org/registry/vulkan/specs/1.2/html/chap36.html#_versions_and_formats),
[filling
buffers](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdFillBuffer.html),
etc., so the driver should have your back in that regard.

```cpp
class SpecConsts {
public:
    SpecConsts()
    {
        update_spec_inf();
    }

    template<class T>
    void add(T n)
    {
        std::size_t size   = sizeof(n);
        std::size_t id     = m_entries.size();
        std::size_t offset = dat.size();

        if (id >= UINT32_MAX) {
            throw std::runtime_error("maximum Vulkan specialization map entry "
                                     "count exceeded");
        }

        if (offset > UINT32_MAX) {
            throw std::runtime_error("maximum Vulkan specialization map entry "
                                     "offset exceeded");
        }

        m_entries.push_back({
            .constantID = static_cast<uint32_t>(id),
            .offset     = static_cast<uint32_t>(offset),
            .size       = size,
        });

        std::byte* p = reinterpret_cast<std::byte*>(&n);
        for (std::size_t i = 0; i < size; ++i) {
            dat.push_back(p[i]);
        }

        update_spec_inf();
    }

    void add(bool n)
    {
        add(static_cast<VkBool32>(n));
    }

    const VkSpecializationInfo* spec_info()
    {
        return &spec_inf;
    }

private:
    std::vector<std::byte> dat;
    std::vector<VkSpecializationMapEntry> m_entries;
    VkSpecializationInfo spec_inf;

    void update_spec_inf()
    {
        spec_inf.mapEntryCount = static_cast<uint32_t>(m_entries.size());
        spec_inf.pMapEntries   = m_entries.data();
        spec_inf.dataSize      = dat.size();
        spec_inf.pData         = dat.data();
    }
};
```

Over in GLSLand, `constant_id` should only be applied to a
`bool`, `int`, `uint`, `float`, or `double`, and should not be
applied to block members. (In the case of a `bool`, you should
store a `VkBool32` on the Vulkan side and set `size` accordingly
in the corresponding map entry; `SpecConsts` does this
automatically for a C++ `bool`.) The variable in question should
also be `const`. `constant_id` takes as a parameter the value of
`constandID` in the map entry; in C++:

```cpp
SpecConsts scs;
scs.add(true);     // constantID = 0
scs.add(-23);      // constantID = 1
scs.add(13);       // constantID = 2
scs.add(777.777f); // constantID = 3
scs.add(DBL_MAX);  // constantID = 4

VkPipelineShaderStageCreateInfo pss_cinf {
    // ...
    .pSpecializationInfo = scs.spec_info(),
};
```

and then in GLSL:

```glsl
layout(constant_id = 0) const bool   frst; // true
layout(constant_id = 1) const int    scnd; // -23
layout(constant_id = 2) const uint   thrd; // 13
layout(constant_id = 3) const float  frth; // 777.777
layout(constant_id = 4) const double ffth; // ~1.7976931348623157e+308
```

You can give variables declared with `constant_id` a default
value that it will be set to if it doesn't receive a value from
the Vulkan side. For instance, in this case we could declare

```glsl
layout(constant_id = 5) const int sxth = 999;
```

and `sxth` would be set to `999` because we didn't specify a
value for a `constantID` of `5` in our `VkSpecializationInfo`.

### The general-purpose standard library

GLSL has a variety of built-in functions and variables. Many of
them exist only to support specific shader stages, and like the
shader-stage-specific layout qualifiers, we'll cover those in our
detailed exploration of them. Some of them are available in any
shader stage, but are also easier to talk about in the context of
the graphics pipeline, like the texture and image functions. Here
we explore the more "general" functions, like those which support
mathematics and bit-twiddling.

These functions aren't guaranteed to have direct hardware
support. However, they are implemented in the driver, at least
generally speaking—even after compiling your shader into SPIR-V,
these functions are usually called via an [extended instruction
set](https://www.khronos.org/registry/spir-v/specs/unified1/SPIRV.html#_a_id_extinst_a_extended_instruction_sets).
You can pass the `-H` flag to glslangValidator to get
human-readable SPIR-V if you'd like to take a look for yourself
(`-Od` turns off optimizations if you'd like to do that as well).

Unless otherwise specified, these functions can accept both
scalars and vectors as input, and operate component-wise on
vectors. Some operate on whole vectors, and some operate on
matrices; these will be noted.

All the built-in functions are covered in the GLSL spec under
["8. Built-In
Functions"](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.html#built-in-functions),
so you can look there if you have questions that aren't answered
here.

#### Trig

All of these map over 32-bit floating point values. They will
never cause a divide-by-zero error, but they are undefined for
some inputs, particularly those that would result in zero
division or those which are outside the domain of the equivalent
real-valued mathematical functions.

##### Units

There are two functions `degrees()` and `radians()` for
converting between degrees and radians. `degrees(n) == 180*n / π`
and `radians(n) == π*n / 180`, as you would expect.

##### The trig functions

There's `sin()`, `cos()`, and `tan()`, all of which take an
argument in radians and behave as you would expect. There are
also their inverses, `asin()`, `acos()`, and `atan()`.

`asin(x)` and `acos(x)` give undefined results for `|x| > 1`.

`atan()` is overloaded; it supports the traditional interface of
both `atan()` and `atan2()`, i.e.

```
          ╭
          │ x  > 0,           atan(y/x)
          │ x  < 0 && y < 0,  atan(y/x) - π
          │ x  < 0 && y > 0,  atan(y/x) + π
atan(y,x) ┤ x == 0 && y > 0,  π/2
          │ x == 0 && y < 0,  -π/2
          │ x == 0 && y == 0, undefined
          ╰
```

##### The hyperbolic trig functions

`sinh()`, `cosh()`, `tanh()`, and their inverses `asin()`,
`acosh()`, and `atanh()`. `acosh(x)` is undefined if `x < 1`, and
`atanh(x)` is undefined if `x >= 1`.

#### Exponential functions

There's `exp()` and `log()` for base-_e_ and `exp2()` and
`log2()` for base-2. `log(x)` and `log2(x)` are undefined for `x
<= 0`.

There's also `pow()`, `sqrt()`, and `inversesqrt()`. `pow(x,y)`
gives <i>x<sup>y</sup></i> and is undefined for `x < 0` and for
`x == 0 && y <= 0`. `sqrt(x)` gives √_x_ and is undefined for `x
< 0`. `inversesqrt(x)` gives `1 / sqrt(x)` and is undefined for
`x <= 0`. `sqrt()` and `inversesqrt()` will work with 64-bit
floating point arguments (`double`, `dvec4`, etc.) as well as
32-bit.

#### Basic real-valued functions

These are defined over a wider variety of types; they all map
over 32-bit and 64-bit floating point values at least.

##### `abs()`

`abs(x)` gives |_x_|.

##### `sign()`

This is defined as:

```
        ╭
        │ x  > 0, 1
sign(x) ┤ x == 0, 0
        │ x  < 0, -1
        ╰
```

It maps over signed integers as well as floating-point values.

##### `fma()`

In general, `fma(a,b,c) == a*b + c`. However, `fma()` is always
considered a single operation; if `a*b + c` is consumed by a
variable qualified with `precise`, it's considered to be two
operations, with the attendant potential differences in
precision and performance.

##### Rounding

There's `floor()`, `ceil()`, `trunc()`, `round()`, and
`roundEven()`. The type of the value they return matches that of
the input (i.e. if `x` is a `double`, `floor(x)` returns a
`double` as well).

`floor(x)` maps `x` to the nearest integer `<= x`, whereas
`ceil(x)` maps `x` to the nearest integer `>= x`.

`trunc(x)` maps `x` to the nearest integer in the direction of 0.

`round(x)` maps `x` to the nearest integer. If the fractional
part of `x` is `0.5`, `x` is rounded in an implementation-defined
direction (probably optimized for speed). If you want more
predictable rounding behavior, you can use `roundEven(x)`, which
rounds `x` towards the nearest even integer when it has a
fractional part of `0.5`.

##### Fractions

`fract()`, `mod()`, and `modf()`.

`fract(x) == x - floor(x)`.

`mod(x,y) == x - y*floor(x/y)`. This has overloads for scalar `y`
even if `x` is a vector, although the component types should
match (i.e. if `x` is a `dvec4`, `y` can be a `double`).

`modf()` takes two parameters and its second is `out`; `mod(x,y)`
returns the fractional part of `x` and sets `y` to the integer
part, like `math.h`'s `modf()`. The types of `x` and `y` should
match. Both `y` and the return value will have the same sign as
`x`.

##### Maxima and minima

`max()`, `min()`, and `clamp()`. These operate over all the
numeric types, and also support the case where the arguments
other than the first can be scalar even if the first argument is
a vector.

`max(x,y)` returns `y` if `x < y` and `x` otherwise.

`min(x,y)` returns `y` if `y < x` and `x` otherwise.

`clamp(x, min_n, max_n) == min(max(x, min_n), max_n)`, but is
undefined if `min_n > max_n`.

##### `step()`

`step(thresh, x)` returns `0.0` if `x < thresh` and `1.0`
otherwise. `thresh` can be scalar even if `x` is a vector,
although both should be of floating-point type.

#### Geometric vector functions

All of these operate on vectors as a whole as opposed to
component-wise.

`length(a)` is ||_a_||, i.e. the norm of `a`, `sqrt(a.x*a.x +
a.y*a.y + a.z*a.z)`.

`distance(a,b)` is ||_a_ - _b_||, i.e. `length(a - b)`.

`dot(a,b)` is _a_ · _b_, i.e. `a.x*b.x + a.y*b.y + a.z*b.z`.

`cross(a,b)` is _a_ × _b_, i.e. `{ a.y*b.z - a.z*b.y, a.z*b.x -
a.x*b.z, a.x*b.y - a.y*b.x }`.

`normalize(a)` is `a / length(a)`, i.e. a vector of the same
direction as `a` but with length 1.

`faceforward(N, I, Nref)` returns `dot(I,Nref) < 0 ? N : -N`. If
`I` is the eye-space position vector of a vertex, `N` and `Nref`
are [surface
normals](https://en.wikipedia.org/wiki/Normal_(geometry\)), and
`Nref` is pointing away from the viewer, `faceforward()` will
return `N` flipped to face the viewer.

`reflect(I,N)`, where `I` is an [incident
vector](https://en.wikipedia.org/wiki/Angle_of_incidence_(optics\))
and `N` is a normal, returns the direction of reflection, i.e. `I
- 2*dot(N,I)*N`.  (Naturally, `N` should be normalized.)

`refract(I, N, eta)`, where `I` is an incident vector, `N` is a
normal, and `eta` is a scalar equal to the ratio of [refractive
indices](https://en.wikipedia.org/wiki/Refractive_index), returns
the [refraction
vector](https://en.wikipedia.org/wiki/Refraction). In C++-like
pseudocode:

```cpp
template(class T)
vector<T> refract(vector<T> I, vector<T> N, T eta)
{
    T k = 1.0 - eta*eta*(1.0 - dot(N,I)*dot(N,I));

    if (k < 0.0) {
        return vector<T>(0.0);
    } else {
        return eta*I - (eta*dot(N,I) + sqrt(k))*N;
    }
}
```

#### Matrix functions

All of these work with both single- and double-precision floating
point matrices and vectors.

`matrixCompMult(x,y)` does component-wise multiplication of `x`
and `y`, since `x * y` does linear-algebra-style matrix
multiplication (see "Operators").

`outerProduct(c,r)` returns _c ⊗ r_, where _c_ and _r_ are
vectors:

```glsl
vec2 c = { m, n };
vec3 r = { e, f, g };

mat3x2 a = outerProduct(c,r);

a == { { m*e, n*e },
       { m*f, n*f },
       { m*g, n*g } }; // true
```

`tranpose(m)` returns the transpose of the matrix _m_:

```glsl
mat3x2 m = { { a, d },
             { b, e },
             { c, f } };

mat2x3 t = transpose(m);

t == { { a, b, c },
       { d, e, f } }; // true
```

`determinant(m)` returns the determinant of the matrix _m_ as a
`float`:

```glsl
mat3 m = { { a, d, g, },
           { b, e, h, },
           { c, f, i, } };

float d = determinant(m);

d == a*e*i + b*g*f + c*d*h - a*f*h - b*d*i - c*g*e; // true
```

`inverse(m)` returns the inverse of _m_, i.e. the matrix
<i>m<sup>-1</sup></i>:

```glsl
mat2 m = { { a, c },
           { b, d } };

mat2 minv = inverse(m);

minv == { {  d / determinant(m), -b / determinant(m) }
          { -c / determinant(m),  a / determinant(m) } };
```

For relatively obvious reasons, `inverse(m)` is undefined in the
case where `determinant(m)` is 0, i.e. `m` is singular. It's also
undefined if `m` is
[ill-conditioned](https://blogs.mathworks.com/cleve/2017/07/17/what-is-the-condition-number-of-a-matrix/).

#### Interpolation

`mix()` does linear interpolation and `smoothstep()` does
post-clamping Hermite interpolation.

`mix(x,y,a) == x*(1 - a) + y*a`. `a` can be scalar even if `x`
and `y` are vectors.

`smoothstep(min_n, max_n, x)` returns `0.0` if `x <= min_n`,
`1.0` if `x >= max_n`, and otherwise performs [smooth Hermite
interpolation](https://en.wikipedia.org/wiki/Smoothstep) between
`0.0` and `1.0` in proportion to how far `x` is between `min_n`
and `max_n`. Sketched in C++:

```cpp
template<class T>
T smoothstep(float min, float max, T x)
{
    T x_scal = (x - min_n) / (max_n - min_n);
    T t = clamp(x_scal, 0.0, 1.0);
    return t * t * (3 - 2*t);
}
```

It's undefined for `min_n >= max_n`. `min_n` and `max_n` can be
scalar even if `x` is a vector.

#### Vector mixing

`mix()` is also a function used to mix-and-match components
between two vectors. With `mix(x,y,a)`, if `x`, `y`, and `a` are
all vectors of the same length and `a` is a vector of `bool`s,
`mix()` will return a new vector of the same length as the
arguments that takes a component from `x` if the corresponding
component of `a` is `false` and takes a component from `y` if the
corresponding component of `a` is `true`. For example:

```glsl
ivec4 x = { 0, 0, 0, 0 };
ivec4 y = { 1, 1, 1, 1 };
bvec4 a = { true, false, true, false };

mix(x,y,a) == { 1, 0, 1, 0 };
```

#### Floating-point operations

##### Infinity and NaN checks

`isnan()` and `isinf()`. If the implementation doesn't support
NaNs, `isnan()` will always return `false`. `isinf(x)` returns
`true` if `x` holds a positive or a negative infinity.

##### Bit-level

`floatBitsToInt()` and `intBitsToFloat()`. These convert between
a `float` and an `int` or `uint` value corresponding to its
underlying representation (IEEE floats always have a sign bit so
the choice of integer type is more-or-less immaterial). If a
value corresponding to a NaN is passed into `intBitsToFloat()`
the result is undefined.

##### Significand and exponent

`frexp()` and `ldexp()`. These work with both 32-bit and 64-bit
floating point types.

`frexp(x, exp)`, where `x` is a floating-point type and `exp` is
a signed integer type, returns the significand of `x` and writes
its exponent into `exp`. If the implementation supports signed 0,
a `-0` input will return a `-0` significand. If `x` is a NaN or
infinity, the result is undefined.

`ldexp(x, exp)` performs the reverse of `frexp(x, exp)`,
returning a floating-point value with a significand of `x` and an
exponent of `exp`. If `exp > 128` for 32-bit input or `exp >
1024` for 64-bit input, the result is undefined. If `exp < -126`
for 32-bit input or `exp < -1022` for 64-bit input, the result
may be flushed to 0. Correspondingly, splitting and then
reconstructing a floating-point value with `frexp()` and
`ldexp()` will result in the same value as long as the original
value is finite and non-subnormal.

##### Packing

`un/packU/Snorm2x16()`, and `un/packU/Snorm4x8()` (i.e.
`packSnorm4x8()`, `unpackUnorm2x16()`, etc.). These convert
between a `uint` and a `vec2` (`*2x16`) or `vec4` (`*4x8`) with
normalized (`0.0`–`1.0` for `*U*` and `-1.0`–`1.0` for `*S*`)
components. The first component of the vector corresponds to the
lowest bits of the `uint`, the last component corresponds to the
highest bits, etc. Each component of the vector maps to the
minimum and maximum values of the bits of the `uint` it
corresponds to.

`packHalf2x16()` and `unpackHalf2x16()`. These convert between a
`uint` and a `vec2` by representing the components of the `vec2`
as 16-bit floating point values and storing them in the high and
low bits of the `uint`. The first component of the `vec2` is
stored in the low bits of the `uint` and the second component is
stored in the high bits. The 16-bit representation is done
according to the host.

`packDouble2x32()` and `unpackDouble2x32()`.
`packdouble2x32(bits)`, where `bits` is a `uvec2`, returns a
`double` with `bits[0]` as its low bits and `bits[1]` as its high
bits. The result is undefined if a NaN or infinity would be
produced. `unpackDouble2x32()` performs the same operation in
reverse.

#### Integer operations

##### Safe arithmetic

`uaddCarry()`, `usubBorrow()`, and `u/imulExtended()`. The `u*`
functions take arguments of unsigned integer type, while
`imulExtended()` takes signed integer arguments.

`uaddCarry(x, y, carry)` returns `x + y` modulo 2<sup>32</sup>,
setting `carry` to `1` if the result would have overflowed and to
`0` otherwise. This effectively allows you to carry out unsigned
integer addition with an extra bit of precision. `usubBorrow()`
is similar; `usubBorrow(x, y, borrow)` returns `x - y`, giving
2<sup>32</sup> plus the result and setting `borrow` to `1` if
negative, `0` otherwise.

`umulExtended()` and `imulExtended()` perform multiplication of
32-bit integers and give a 64-bit result; `u/imulExtended(x, y,
msb, lsb)` returns the high bits of `x * y` in `msb` and the low
bits in `lsb`.

##### Bitfield

`bitfieldExtract()`, `bitfieldInsert()`, `bitfieldReverse()`,
`bitCount()`, `findLSB()`, and `findMSB()`. These are for working
with integer types as collections of bits.

`bitfieldExtract(val, offset, bits)` returns `bits` bits from
`val` starting at `offset`, stored in the low bits of the result.
`val` can be of signed or unsigned integer type but `offset` and
`bits` are always `int`, so if `val` is a vector the same
`offset` and `bits` will be used for all its components. However,
the result is undefined if `bits` or `val` is negative. It's also
undefined if `offset + bits` is greater than the number of bits
in `val`. If `val` is a signed type, the result will be
sign-extended from the highest bit in the selection.

`bitfieldInsert(base, insert, offset, bits)` takes `bits` bits
from `insert` starting from the low bits and gives a result with
those bits inserted at `offset` and all other bits taken from
`base`. As with `bitfieldExtract()`, `offset` and `bits` are both
`ints`s, but the result is undefined if either is negative.
`bits` can be `0`, though, in which case the result will be equal
to `base`.

`bitfieldReverse(n)` returns `n` with its bits reversed. It takes
both signed and unsigned arguments.

`bitCount(n)` returns the number of one bits in `n`. It takes
both signed and unsigned arguments but always returns a signed
argument for some reason.

`findLSB(n)` returns the index of the lowest one bit in `n`. If
`n == 0`, it returns `-1`.

`findMSB(n)` returns the highest one bit of `n` if it's unsigned
or positive and the highest zero bit if it's negative. It returns
`-1` if `n == 0` or `n == -1`.

#### Vector comparison

The comparison operators such as `==`, `<`, etc. always return
scalars, and some of them won't operate on vectors. These
functions perform the same role but are vector-oriented.

There are two unary functions that don't have an equivalent in
the scalar operators, `any()` and `all()`. They both take a
Boolean vector. `any(v)` returns `true` if any of the components
of `v` is true, whereas `all(v)` returns `true` only if all the
components of `v` are true.

The other functions have direct equivalents to scalar operators,
so I've summarized them in this table. All return a Boolean
vector equal in length to their argument(s), with the operation
performed component-wise.

Function           | Operator
------------------ | --------
lessThan()         | <
lessThanEqual()    | <=
greaterThan()      | >
greaterThanEqual() | >=
equal()            | ==
notEqual()         | !=
not()              | !

#### Invocation and memory control

You have to explicitly synchronize shader invocations if that's
something you require. GLSL gives you a few tools to do this. You
can call the function `barrier()` in tesselation control and
compute shaders to synchronize control flow and memory access
between invocations in the same patch/workgroup, and you can call
the `*memoryBarrier*()` functions to synchronize memory access
alone in any shader stage.

You should only call these functions in places that every
invocation is guaranteed to reach. If you call them inside of a
conditional branch that only some invocations reach, those
invocations will wait forever for their partners to reach the
same call site.

##### `barrier()`

You can only call `barrier()` in a tessellation control or
compute shader. In either case, when an invocation reaches a
`barrier()`, it stops and waits for all the other invocations in
its patch or workgroup to reach the `barrier()` as well before
continuing.  This ensures that each invocation in the
patch/workgroup is at the same point in terms of control flow.
Also, if an invocation writes to a tessellation control output
variable or a `shared` compute shader variable before the
`barrier()`, the results will be visible to all the other
invocations in the patch/workgroup after the `barrier()`.

In a tesselation control shader, you can only call `barrier()`
inside of `main()`. In a compute shader, you can call it anywhere
you like, provided that all invocations are guaranteed to reach
the call site.

If you need to synchronize access to a variable that's not a
tessellation control output variable or `shared` compute shader
variable from a tessellation control or compute shader, you
should use both `barrier()` and one of the memory barrier
functions one after the other.

##### `*memoryBarrier*()`

These functions create a memory barrier between shader
invocations in the same program. The most general is
`memoryBarrier()`, but there's also
`memoryBarrierAtomicCounter()`, `memoryBarrierBuffer()`, and
`memoryBarrierImage()`, as well as `groupMemoryBarrier()` and
`memoryBarrierShared()` for compute shaders.

When you call `memoryBarrier()`, any writes an invocation in the
program has performed to memory that other invocations can access
becomes visible to those invocations.
`memoryBarrierAtomicCounter()`, `memoryBarrierBuffer()`, and
`memoryBarrierImage()` are the same, but they apply only to
atomic counters, buffers, and images respectively.

In a compute shader, you can also use `groupMemoryBarrier()` to
create a memory barrier just within a shader's workgroup.
`memoryBarrierShared()` creates a memory barrier only for shared
variables within a shader's workgroup, but you don't need to use
it as of GLSL 4.60 as long as you call `barrier()`.

In general, for tessellation control and compute shaders, these
functions aren't sufficient to order accesses within a single
patch/workgroup; you also need to call `barrier()` on top of a
memory barrier function (see "`barrier()`" above). If you're just
trying to synchronize access to a tessellation control output
variable or `shared` variable, you can use `barrier()` alone,
without calling a memory barrier function.

## Rendering in detail

We've arrived at last. Take a moment to savor the view from up
here—we've had to clamber over a rather immense amount of
material to make it to this spot. With all the knowledge you've
gained, you're now in a good position to understand how Vulkan
draws imagery front-to-back. Hurrah!!

### Approaching the graphics pipeline

We've touched on the graphics pipeline here and there, but of
course we've glossed over a lot of the details until now. We're
going to really pick it apart piece-by-piece from here on out,
but we won't have fully covered it until the end of this section,
since Vulkan's rendering behavior is deeply intertwined with the
structure of the graphics pipeline.

If you've taken a look at
[`VkGraphicsPipelineCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkGraphicsPipelineCreateInfo.html),
you'll have noted that it's one of the most baroque structures in
all of Vulkan. A whole render pass is just _one_ of its
parameters, after all! Luckily we've covered those already, so
now we can get into the various `*State` parameters, which
configure aspects of Vulkan's rendering behavior.

Throughout this section, we'll weave back and forth between
Vulkan and GLSL, showing how actions taken on one side impact the
other. As you've heard, the graphics pipeline moves through a
series of stages, so we can start at the beginning and walk
through it until we reach the end.

### Graphics pipeline creation and binding

All the intricacies of
[`VkGraphicsPipelineCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkGraphicsPipelineCreateInfo.html)
aside, graphics pipelines are created with
[`vkCreateGraphicsPipelines()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCreateGraphicsPipelines.html).
This actually takes an array of
[`VkGraphicsPipelineCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkGraphicsPipelineCreateInfo.html)s
so you can batch pipeline creation for the sake of efficiency. It
also takes a pipeline cache handle (see "Cache" under "Pipelines"
if you need a refresher on that).

Once you've got a graphics
[`VkPipeline`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipeline.html)
ready to go, you can bind it to a command buffer with
[`vkCmdBindPipeline()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindPipeline.html).
Aside from the command buffer and pipeline handles, this has a
parameter <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineBindPoint.html">VkPipelineBindPoint</a>
pipelineBindPoint</code>
which specifies the type of pipeline to bind. In this case, you
would use `VK_PIPELINE_BIND_POINT_GRAPHICS` (See "Binding to a
command buffer" for more on this command.)

This is also a good time to bind any descriptor sets you might
want to use in conjunction with the pipeline—see "Binding
descriptor sets" under "Resource descriptors" for more on that.

### Vertex processing

Work in a graphics pipeline begins with the submission of
vertices. What exactly a "vertex" is is up to you to some degree,
however. Perhaps the most appropriate way to think of a vertex is
simply as data that accompanies a vertex shader invocation—they
_can_ represent the points in space that make up a 3D model, but
they don't have to.

#### The structure of a vertex

The input variables you declare in your vertex shader describe
the format of the vertex data it expects. For example, let's say
we had the following input block declaration in a vertex shader:

```glsl
layout(location = 0) in mesh_attrs {
    vec3 pos;
    vec3 norm;
};
```

If these are the only inputs declared in our vertex shader, we
now have a precise specification of how to lay out our vertex
data on the Vulkan side for submission. This declaration puts
`pos` at location 0 and `norm` at location 1 (see "`location` and
`component`" under "Layout qualifiers" if this is confusing to
you). The declaration `vec3` tells us that we need 3 32-bit
floating point values for each location (we'll get into the
specifics in just a moment).

Vertex data is stored in
[`VkBuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBuffer.html)s.
In this case, the data in our buffer might look like this:

```cpp
float mesh_attrs[] = { 6.98, 2.70, 9.91,
                       0.31, 0.84, 0.45,
                       1.86, 2.62, 5.87,
                       0.44, 0.88, 0.20,
                       /* ... */         };
```

One of the parameters used to create a graphics pipeline is a
[`VkPipelineVertexInputStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html).
This consists mainly of two arrays: an array of
[`VkVertexInputBindingDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputBindingDescription.html)s
and an array of
[`VkVertexInputAttributeDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputAttributeDescription.html)s.

A
[`VkVertexInputBindingDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputBindingDescription.html)
describes a place where a vertex buffer can be bound. This is
done with the `uint32 binding` parameter, which you can set to
whatever you like (within
`VkPhysicalDeviceLimits::maxVertexInputBindings`, which is [most
commonly 32 but can be as low as
16](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxVertexInputBindings)
as of July 2021). It also has a `uint32_t stride` parameter,
where you specify how wide an individual block of vertex input
data is in the bound buffer (within
`VkPhysicalDeviceLimits::maxVertexInputBindingStride`, which is
[most commonly 2048 but is sometimes as high as
16383](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxVertexInputBindingStride)
as of July 2021). The last parameter is <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputRate.html">VkVertexInputRate</a>
inputRate</code>, which will be easier to explain shortly when we
discuss draw commands.

In this case, our vertex input binding description for this
buffer might look like this:

```cpp
uint32_t mesh_attrs_bind_ndx = 0;
uint32_t mesh_attrs_stride = static_cast<uint32_t>(sizeof(float) * 6);

std::vector<VkVertexInputBindingDescription> bind_descs {
    {
        .binding   = mesh_attrs_bind_ndx,
        .stride    = mesh_attrs_stride,
        .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
    },
};
```

A
[`VkVertexInputAttributeDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputAttributeDescription.html)
is a per-location description of the data in a vertex buffer. The
location number is given in `uint32_t location`, and there's also
a `uint32_t binding` parameter for the binding number of the
bound vertex buffer. <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkFormat.html">VkFormat</a>
format</code> describes the format of the data in memory for this
location. Note that this format must be allowed as a vertex
buffer format; fortunately, many formats are required to be
supported for this use [by the
spec](https://www.khronos.org/registry/vulkan/specs/1.2/html/chap33.html#features-required-format-support)
including all those you would probably want, but you can check
with
[`vkGetPhysicalDeviceFormatProperties()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkGetPhysicalDeviceFormatProperties.html)
if you'd like. The last parameter is `uint32_t offset`, which is
where you specify the offset from the start of an individual
element to begin reading data at (within
`VkPhysicalDeviceLimits::maxVertexInputAttributeOffset`, which is
[most commonly 2047 but is sometimes as high as
4294970000](https://vulkan.gpuinfo.org/displaydevicelimit.php?name=maxVertexInputAttributeOffset)
as of July 2021).

In this case, our vertex input attribute descriptions might look
like this (note that you can use
[SPIRV-Reflect](https://github.com/KhronosGroup/SPIRV-Reflect) to
get this information from your compiled shader sources):

```cpp
VkFormat coords_fmt = VK_FORMAT_R32G32B32_SFLOAT; // this means "3 32-bit
                                                  // floats"...don't mind the
                                                  // RGB stuff
uint32_t mesh_attrs_pos_loc  = 0;
uint32_t mesh_attrs_norm_loc = 1;

uint32_t mesh_attrs_pos_offs  = 0;
uint32_t mesh_attrs_norm_offs = static_cast<uint32_t>(sizeof(float) * 3);

std::vector<VkVertexInputAttributeDescription> attr_descs {
    {
        .location = mesh_attrs_pos_loc,
        .binding  = mesh_attrs_bind_ndx,
        .format   = coords_fmt,
        .offset   = mesh_attrs_pos_offs,
    },

    {
        .location = mesh_attrs_norm_loc,
        .binding  = mesh_attrs_bind_ndx,
        .format   = coords_fmt,
        .offset   = mesh_attrs_norm_offs,
    },
};
```

We could make a
[`VkPipelineVertexInputStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineVertexInputStateCreateInfo.html)
with these as follows:

```cpp
VkPipelineVertexInputStateCreateInfo vert_inpt_inf {
    .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    .pNext = nullptr,
    .flags = 0,
    .vertexBindingDescriptionCount   = bind_descs.size(),
    .pVertexBindingDescriptions      = bind_descs.data(),
    .vertexAttributeDescriptionCount = attr_descs.size(),
    .pVertexAttributeDescriptions    = attr_descs.data(),
};
```

If we make a graphics pipeline with these, it will know how to
work with our vertex buffers. But how do we actually use these
buffers?

#### Vertex submission

Work in a graphics pipeline can be initiated with a draw command
once you've bound the pipeline in question and the vertex buffers
you want to use to the command buffer. If you're going to do an
indexed draw, you'll also want to bind an index buffer
beforehand.

##### What's an index buffer?

We'll get into the technical details of binding vertex and index
buffers and recording draw commands momentarily, but just so you
know what I'm talking about while we do this, draw commands can
be organized into indexed and non-indexed categories. The
non-indexed commands just go through the vertex buffers and submit
vertices one-by-one. The trouble with this is that, during
tessellation, a certain number of vertices will be needed to make
up each primitive; for example, in the most common case of
triangles, you would need three vertices per primitive (we'll get
into all this in detail soon). If you wanted to render a square
then, you might think you would need four vertices, one for each
corner—but if you weren't using an indexed draw command, you
would actually need six elements in your vertex buffers for this,
because it takes two triangles to make a square:

![A rectangle with overlapping
vertices.](pics/overlapping_verts.svg)

Unfortunately, two of the elements in your vertex buffers would
be redundant in this case, because they would perfectly duplicate
the data of two of the other elements. I've drawn the vertices in
question slightly offset from each other here, but in practice
they would perfectly overlap, bloating your vertex buffers.

With an index buffer, you can specify the order in which to
assemble the vertices into primitives explicitly. The advantage
of this is that vertices can be reused, which avoids the need to
duplicate vertices used to assemble more than one primitive. Even
if you don't mind the extra overhead, the models output by 3D
modeling programs usually work this way, so it's still worth
getting comfortable with indexed draws.

##### Binding vertex buffers

Once you've got your vertex buffers ready, you can bind them to a
command buffer with
[`vkCmdBindVertexBuffers()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindVertexBuffers.html).
You can bind all the vertex buffers you need to fill all of the
bindings you defined during graphics pipeline creation in one go
with this command, or just update subset of them; it takes
parameters `uint32_t firstBinding` and `uint32_t bindingCount`
for the binding number to start with and the number of bindings
to update starting from there, respectively. Aside from those, it
takes an array of the vertex buffers themselves, as well as an
array <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceSize.html">VkDeviceSize</a>\*
pOffsets</code> which can be used to specify offsets to start at
for each buffer. If you're storing all your vertex data in one
large buffer, you can just specify offsets into it for each block
of vertex data corresponding to each respective binding you've
defined (and just pass the same buffer handle repeatedly for each
binding).

You can submit this command repeatedly for the same graphics
pipeline; repeated submissions will update the relevant bindings
with new data.

##### Binding an index buffer

The contents of an index buffer might look like this:

```cpp
uint16_t indices[] = { 0, 1, 2, 3, 1, 0, /* ... */ };
```

These are indices into the vertex buffers. They can be either
16-bit or 32-bit unsigned integers. If you use 16-bit, it means
less data to copy into the
[`VkBuffer`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBuffer.html)
beforehand if you have 65,536 or less vertices in the draw call.

Just to be clear, these indices are used to assemble a vertex
using the data from each block of bound vertex data. So, an index
of `0` would take data from the offset defined for each binding
to assemble a vertex, an index of `1` would take data from 1 past
each offset, etc. That's why you can bind multiple vertex buffers
(one per vertex input binding) but only a single index buffer.

(Vertex buffers bound to bindings with an input rate of
[`VK_VERTEX_INPUT_RATE_INSTANCE`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputRate.html)
aren't included in this, as they're not addressed via the vertex
index—more on that shortly.)

You can bind an index buffer to your command buffer with
[`vkCmdBindIndexBuffer()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdBindIndexBuffer.html)
(buffer buffer buffer). In addition to the index buffer handle
itself, this takes a <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceSize.html">VkDeviceSize</a>
offset</code> into the buffer if you'd like, as well as a
<code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkIndexType.html">VkIndexType</a>
indexType</code> which you can use to specify whether you're
using 16-bit or 32-bit indices. When you submit an indexed draw
command, these indices will be read in, zero-extended to 32 bits
if they have less than that, and then added to the offset for the
binding to calculate the ultimate index into the vertex buffer in
question. So, even if you need to read from indices past the
65,536 mark, you can still use 16-bit indices if you want as long
as you don't have more than 65,536 vertices in total for the draw
call.

##### Recording a draw command

Aside from binding your graphics pipeline, vertex buffers,
possibly an index buffer, and any descriptor sets, you also need
to begin a render pass before you can record draw commands (see
"Render passes"). The role the render pass plays in all this
becomes particularly clear in the context of fragment shading, so
we'll go into it more there, but for now you can just note that
draw commands won't work outside of the context of a render pass.
Once you've got all the context in place, you can kick off
rendering (although, of course, that won't actually happen until
you submit the command buffer to a queue).

The most straightforward draw command is
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html).
This does a non-indexed draw, so an index buffer isn't involved.
As you might expect, it has `uint32_t firstVertex` and `uint32_t
vertexCount` parameters for the index of the first vertex to
start with in the vertex buffers and the number of vertices to
use in the draw call from there. However, it also has `uint32_t
firstInstance` and `uint32_t instanceCount` parameters, which
might seem a little more cryptic to you right now. This can be
used to submit the specified set of vertices more than once, also
known as _instanced rendering_ or _instancing_.

###### Vertices and instances

You might recall from just a bit ago in "The structure of a
vertex" that
[`VkVertexInputBindingDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputBindingDescription.html)
has a parameter <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputRate.html">VkVertexInputRate</a>
inputRate</code>, which we didn't really go into at the time.
This is connected to these two "instance" parameters in
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html),
and all of this has a connection to the language of the vertex
shader itself.

We've alluded a little bit to built-in variables in GLSL, but we
have yet to actually look at any. In a vertex shader, these four
variables are implicitly defined:

```cpp
in int gl_BaseVertex;
in int gl_BaseInstance;

in int gl_VertexIndex;
in int gl_InstanceIndex;
```

`gl_BaseVertex` is set to `firstVertex` for non-indexed draws;
for an indexed draw, it's set to `vertexOffset` (we'll cover this
in just a moment).

`gl_BaseInstance` is set to `firstInstance` with all draw
commands.

When using
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html),
`gl_VertexIndex` will take on the values `firstVertex`,
`firstVertex + 1`, …, `firstVertex + (vertexCount - 1)`.
`gl_InstanceIndex` will take on the values `firstInstance`,
`firstInstance + 1`, …, `firstInstance + (instanceCount - 1)`,
but it will only increment after one complete cycle through the
vertices.

```cpp
VkCommandBuffer cmd_buff; // ready for a draw call
uint32_t vert_cnt = 3;
uint32_t inst_cnt = 3;
uint32_t vert_fst = 0;
uint32_t inst_fst = 0;

vkCmdDraw(cmd_buff, vert_cnt, inst_cnt, vert_fst, inst_fst);

// gl_VertexIndex == 0; gl_InstanceIndex == 0;
// gl_VertexIndex == 1; gl_InstanceIndex == 0;
// gl_VertexIndex == 2; gl_InstanceIndex == 0;
// gl_VertexIndex == 0; gl_InstanceIndex == 1;
// gl_VertexIndex == 1; gl_InstanceIndex == 1;
// gl_VertexIndex == 2; gl_InstanceIndex == 1;
// gl_VertexIndex == 0; gl_InstanceIndex == 2;
// gl_VertexIndex == 1; gl_InstanceIndex == 2;
// gl_VertexIndex == 2; gl_InstanceIndex == 2;
```

The purpose of <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputRate.html">VkVertexInputRate</a>
inputRate</code>
in
[`VkVertexInputBindingDescription`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkVertexInputBindingDescription.html)
is to specify whether the bound vertex buffer will be indexed
into by vertex index or by instance index. If it's set to
`VK_VERTEX_INPUT_RATE_INSTANCE`, any input variables in the
vertex shader associated with that input buffer will only have
their values updated with each new _instance_ instead of each new
vertex.

One thing you could do with this is a classic starfield effect:

[![Starfield
effect](pics/StarfieldSimulation.gif)](pics/StarfieldSimulation.gif)

Each of the stars has the exact same shape (a circle). You could
therefore store the vertex information for a single, abstract
circle at one vertex input binding and store the position of each
star instance at another binding. If you set the first binding as
`VK_VERTEX_INPUT_RATE_VERTEX`, set the second as
`VK_VERTEX_INPUT_RATE_INSTANCE`, and set `instanceCount` to the
number of stars you want to draw, you can get the effect without
having to pass a lot of repetitive vertex information. (Of
course, there are other strategies you could use aside from this
too that might be even more efficient—this is just an example.)

###### Indexed draw

If you want to use an index buffer, you can use
[`vkCmdDrawIndexed()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexed.html)
instead of
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html).
This is almost the same. Instead of `uint32_t firstVertex` and
`uint32_t vertexCount`, though, you have `uint32_t firstIndex`,
`uint32_t indexCount`, and `int32_t vertexOffset`. These are
pretty self-explanatory: `firstIndex` is the starting index into
the index buffer, `indexCount` is the number of indices to use in
the draw call, and `vertexOffset` is an offset added to the index
pulled from the index buffer before using it to index into a vertex
buffer.

The indices pulled from the index buffer are zero-extended to 32
bits before `vertexOffset` is added to them, so if you're using
16-bit indices you don't have to fret about overflow as much as
you might otherwise.

Since
[`vkCmdDrawIndexed()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexed.html)
has the same `uint32_t firstInstance` and `uint32_t
instanceCount` parameters as
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html),
you might wonder how this command handles instancing. It's pretty
simple, really: each bound `VK_VERTEX_INPUT_RATE_VERTEX` buffer
is indexed into based on the calculated vertex index from the
index buffer, and each bound `VK_VERTEX_INPUT_RATE_INSTANCE`
buffer is indexed into based on the instance index just like with
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html).
The only difference in how the instance index is determined is
that it's based on `uint32_t firstIndex` and `uint32_t
indexCount` instead of `uint32_t firstVertex` and `uint32_t
vertexCount`.

###### Indirect draw

It may have occurred to you at some point that you could generate
vertex data on the GPU. If you did think of this, it may not have
been entirely clear how you should make use of such data
afterwards, since the draw commands we've discussed so far get
their vertex data from buffers bound to the command buffer on the
host side prior to recording the draw call. A particularly
efficient approach is to use an _indirect drawing command_, which
gets its draw parameters from a buffer and can take data from
vertex buffers specified mid-render.

[`vkCmdDrawIndirect()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndirect.html)
is the indirect equivalent of
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html).
This has a parameter <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBuffer.html">VkBuffer</a>
buffer</code> which should be the handle to a buffer containing
[`VkDrawIndirectCommand`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDrawIndirectCommand.html)
structures. These structures specify the same parameters as taken
by
[`vkCmdDraw()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDraw.html),
but of course they can be specified at any time before the
[`vkCmdDrawIndirect()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndirect.html)
executes. There's also <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDeviceSize.html">VkDeviceSize</a>
offset</code> which specifies an offset in bytes where the
[`VkDrawIndirectCommand`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDrawIndirectCommand.html)
structures begin in the `buffer`, a `uint32_t drawCount`
parameter for how many draws to perform (which can be zero), and
a `uint32_t stride` parameter for how far apart each
[`VkDrawIndirectCommand`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDrawIndirectCommand.html)
structure is from the next.

There's also
[`vkCmdDrawIndexedIndirect()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexedIndirect.html),
which is naturally the indirect equivalent of
[`vkCmdDrawIndexed()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexed.html).
This has the same parameters as
[`vkCmdDrawIndirect()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndirect.html),
but expects a buffer with
[`VkDrawIndexedIndirectCommand`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDrawIndexedIndirectCommand.html)
structures instead, which naturally express the same parameters
as
[`vkCmdDrawIndexed()`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/vkCmdDrawIndexed.html).

When performing an indirect draw, there's a special variable
defined in the vertex shading language you can use to get the
index of the current
[`VkDrawIndirectCommand`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDrawIndirectCommand.html)
or
[`VkDrawIndexedIndirectCommand`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkDrawIndexedIndirectCommand.html)
being executed:

```glsl
in int gl_DrawID;
```

This variable is otherwise set to `0`.

### Primitive assembly

At the outset of a draw call, each vertex (i.e. a block of data
being pulled out of your vertex buffers) becomes part of a
_primitive_. This data structure plays some role either directly
or indirectly in every shading stage of a graphics pipeline.

A field <code>const <a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineInputAssemblyStateCreateInfo.html">VkPipelineInputAssemblyStateCreateInfo</a>\*
pInputAssemblyState</code> in
[`VkGraphicsPipelineCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkGraphicsPipelineCreateInfo.html)
configures primitive assembly.  This structure is at once simple
and complex. The only essential field is <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPrimitiveTopology.html">VkPrimitiveTopology</a>
topology</code>, which is an enum. However, this enum has a fair
amount of conceptual density.

#### Structure of a primitive

A primitive is a graph with vertex nodes. Each vertex in a
primitive is assigned zero or more edges in accordance with the
topology of the primitive and the position the vertex occurs at
in the sequence of vertices.

In some topologies there are _adjacency_ vertices and edges.
These are only accessible in a geometry shader; to other shaders,
it's as if they don't exist. Typically, you would do an indexed
draw and use the adjacency vertices for the vertices surrounding
the main ones.

One vertex is labeled the _provoking vertex_ at this stage unless
the patch list topology is used. This is generally the first
non-adjacency vertex in the primitive.

Each topology has a diagram accompanying it that illustrates the
structure of the primitives it implies. Here's the key for
reading the diagrams:

| Symbol                              | Meaning                                                                 |
|-------------------------------------|-------------------------------------------------------------------------|
| ![diagram](pics/vertex.svg)         | The <i>x</i>th vertex in the draw call                                  |
| ![diagram](pics/prov_vertex.svg)    | The provoking vertex                                                    |
| ![diagram](pics/adj_vertex.svg)     | An adjacency vertex                                                     |
| ![diagram](pics/edge.svg)           | A regular edge                                                          |
| ![diagram](pics/adj_edge.svg)       | An adjacency edge                                                       |
| ![diagram](pics/line_nodes.svg)     | Vertices in a line are grouped from left to right                       |
| ![diagram](pics/triangle_nodes.svg) | Vertices in a triangle are grouped clockwise from the provoking vertex  |

#### Primitive topologies

At this stage, the edges of a primitive and its provoking vertex
are mainly significant for fragment shading. If you're using flat
shading, the data accompanying the provoking vertex for fragment
shading (like material parameters) will be used for every vertex
in the primitive. If not, the values of those data points will be
interpolated along the edges of the primitive for every fragment.
We'll discuss this in more detail when we talk about
rasterization, but you can use this information here to help
yourself imagine what each topology might be useful for.

Also, any of these topologies can be used in conjunction with a
geometry shader to guide the procedural generation of geometry in
a scene. Which you should use depends on the kind of input data
your geometry shader needs; the topologies with adjacency are
intended specifically for this purpose, in case your geometry
shader would benefit from some extra context. Looking at the
toplogies from this angle puts them in a different light than
considering them from the perspective of fragment shading.

Regarding the topologies with adjacency, also, the example use
cases I've given all concern GPU-based physics simulations. This
is a fairly obvious application for these topologies as the
adjacency information is useful for that purpose. However, that
style of GPU-based physics dates to before the introduction of
compute shaders, which in many cases will be both simpler _and_
more efficient to use for GPU-based physics than via graphics
shading using topologies with adjacency. The latter approach
generally involves transform feedback and multiple draw calls to
account for all the constraints on the simulation; you can see an
example implementation of a cloth simulation using this method in
[this 2007 whitepaper from
Nvidia](http://developer.download.nvidia.com/whitepapers/2007/SDK10/Cloth.pdf),
which was published a couple years before DX11 introduced compute
shaders. The inclusion of these topologies in Vulkan is helpful
for porting older applications to Vulkan that work this way, but
may not be the best approach for new applications that can start
fresh.

The patch list topology is intended specifically for use with
tessellation. The idea there is that you can pick a number of
vertices to make up a _patch_ and then fill in the space between
them using tessellation control and evaluation shaders. This
presents an alternate route for procedurally generating geometry,
although you can also use tessellation and geometry shading
together. We'll get into all of this in more detail after this
section.

##### Point list

![diagram](pics/point_list.svg)

This is the simplest topology: one node, no edges. Each vertex
defines a single primitive unto itself, with each being
considered its own provoking vertex. There are as many primitives
as vertices. The `topology` setting for this one is
`VK_PRIMITIVE_TOPOLOGY_POINT_LIST`.

The primitives of a point list topology specify discrete points
in space. This could be used for sparks or fireflies.

##### Line list

![diagram](pics/line_list.svg)

Line lists have two nodes and one edge. No vertices are shared
between primitives, so there will be half as many primitives as
there are vertices in the draw call. The `topology` setting for
this one is `VK_PRIMITIVE_TOPOLOGY_LINE_LIST`.

The primitives of a line list topology specify discrete lines in
space. This could be used for lasers, shattering wireframe
models, or cartoon-style motion lines.

##### Line strip

![diagram](pics/line_strip.svg)

Line strips have two nodes and one edge like line lists, but the
second vertex of one line primitive also serves as the provoking
vertex of the next line primitive. As a result, every vertex
aside from the starting and ending vertices is present in two
primitives, and the total number of primitives will be one less
than the total number of vertices. The `topology` setting for
this one is `VK_PRIMITIVE_TOPOLOGY_LINE_STRIP`.

The primitives of a line strip topology specify subsegments of a
single line segment in space. This could be used for neon signs,
ropes, or symbolic sound or radio waves.

##### Triangle list

![diagram](pics/triangle_list.svg)

Triangle lists have three nodes and three edges. The provoking
vertex is connected to the vertex after it, that vertex is
connected to the vertex after it, and that vertex is connected
back to the provoking vertex. The next vertex starts a new
primitive, so the total number of primitives will be a third of
the number of vertices.  The `topology` setting for this one is
`VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST`.

The primitives of a triangle list topology specify discrete
triangles in space. The section of a plane bounded by the edges
of a triangle list primitive defines its _face_, which we'll
discuss more when we get into rasterization. In conjunction with
indexing, this is the topology most commonly used for 3D model
mesh data in this day and age.

##### Triangle strip

![diagram](pics/triangle_strip.svg)

Triangle strips also have three nodes and three edges, but they
share vertices between primitives. Going one-by-one through the
vertices, each vertex and the two after it are used to make up a
primitive, so they're all connected at the edges.  Note that the
pattern is `{0,1,2}, {1,3,2}, {2,3,4}, {3,5,4}, …`, which helps
to ensure they're all facing outwards (as before, we'll discuss
this more when we get into rasterization). There will be two less
primitives then there are vertices with this topology, and the
`topology` setting for this one is
`VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP`.

The primitives of a triangle strip topology specify pieces of
a surface in space. This used to be the most common topology used
for mesh data. However, it may have occurred to you that you
could get the exact same set of primitives this topology would
give you by using triangle lists and indexing, and that approach
is more flexible than using triangle strips. For arbitrary mesh
data, one triangle strip may not be sufficient to represent the
entire mesh, and it may still be necessary to repeat vertices in
some cases. Using a triangle list and indexing ensures that you
can represent the entire mesh without any redundant vertex data,
and that you can fit it all into a single draw call.

Of course, if you _can_ represent your mesh perfectly with a
single triangle strip, your index buffer only needs to be a third
as long as with a triangle list. If you only need to render a
very long and complicated ribbon, that might be a win.

##### Triangle fan

![diagram](pics/triangle_fan.svg)

The primitives of this topology are triangles that all share one
vertex in common—the first vertex in the draw call. The name
comes from how the triangles "fan out" from this center vertex.
As you can see, the center vertex is always the last vertex in
the primitive, so it's never the provoking vertex (otherwise it
would influence multiple faces when flat shading). As with
triangle strips, there will be two less primitives then vertices.
The `topology` setting for this one is
`VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN`.

Like triangle strips, triangle fans have been largely replaced by
indexed triangle lists in this day and age, and for the same
reasons. That said, they're more efficient than triangle strips
at representing convex polygons with more than four sides,
because a triangle strip would have to repeat the center vertex
over and over to describe the same geometry. If you found
yourself back in the '90s and wanted to model, say, a wheel of
cheese, two triangle fans for the top and bottom and a triangle
strip for the side could help cut down on the number of
overlapping vertices.

##### Line list with adjacency

![diagram](pics/line_list_w_adj.svg)

Now we're getting into the "adjacency" topologies. This one is
the simplest to describe: every four vertices makes up a
primitive, with the outer vertices being the adjacency vertices
and the second vertex being the provoking vertex. The number of
primitives will be a fourth of the number of vertices. The
`topology` setting for this one is
`VK_PRIMITIVE_TOPOLOGY_LINE_LIST_WITH_ADJACENCY`.

One use for a line list with adjacency is to perform a GPU-driven
fluid physics simulation, treating the nodes as particles and
using the adjacency information to help refine the simulation.
Out of all the topologies with adjacency, this one is the most
general, so it's well-suited to something like liquid if you need
to model droplets and so on. Remember from the beginning of this
section, though, that a compute shader is likely to be easier and
more efficient to use for this purpose, so you may prefer that
approach if you can freely choose between either.

##### Line strip with adjacency

![diagram](pics/line_strip_w_adj.svg)

True to its name, this one uses the line strip pattern, but with
four vertices instead of two. As such, the total number of
primitives will be three less than the number of vertices. The
`topology` setting for this one is
`VK_PRIMITIVE_TOPOLOGY_LINE_STRIP_WITH_ADJACENCY`.

This would be useful to physically model a rope or chain, or a
stream of liquid depending on the level of detail you want.

##### Triangle list with adjacency

![diagram](pics/triangle_list_w_adj.svg)

This one uses the triangle list pattern, but with a vertex
in-between each vertex in a regular triangle list, making a
larger triangle. The even-numbered vertices make up the "real"
triangle primitive inside the larger triangle. There will be a
sixth as many primitives as vertices, and the `topology` setting
for this one is
`VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY`.

This is very nearly as general as a line list with adjacency, and
could similarly be used for a complex fluid simulation or mesh
deformation. It might be more efficient than a line list with
adjacency depending on the specific case, but again, a compute
shader may be more efficient than using either for this purpose.

##### Triangle strip with adjacency

![diagram](pics/triangle_strip_w_adj.svg)

Roughly speaking, this one is similar to triangle strips in the
way that triangle lists with adjacency are similar to triangle
lists: the inner, "real" triangles form a triangle strip in the
same manner as a triangle strip without adjacency. However, the
ordering this forces on the vertices for the primitive as a whole
is far more involved. As you can see, the first primitive is
special-cased, and then an alternating pattern is used until the
last primitive. The last primitive follows one of two patterns
depending on whether the total number of primitives is even or
odd. These three diagrams describe the whole algorithm in full:

![diagram](pics/triangle_strip_w_adj_first.svg)

![diagram](pics/triangle_strip_w_adj_mid.svg)

![V = # of vertices; P = (V-4)/2 (integer division)](pics/triangle_strip_w_adj_last.svg)

_P_ is the total number of primitives, if that wasn't already
clear. The `topology` setting for this one is
`VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP_WITH_ADJACENCY`.

Similarly to how a triangle list with adjacency could be used in
place of a line list with adjacency, a triangle strip with
adjacency could make a more efficient substitute for a line-based
topology or a triangle list with adjacency when designing a cloth
simulation, especially if the cloth is in a shape that's easy to
represent using a triangle strip (like a rectangle).

##### Patch list

This topology doesn't lend itself as well to being diagrammed as
the others. The number of vertices in the type of primitive it
defines is user-configurable; specifically, it's equal to the
value of
[`VkPipelineTessellationStateCreateInfo::patchControlPoints`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineTessellationStateCreateInfo.html#_members),
which you can set during graphics pipeline creation. The manner
in which space is portioned by these primitives is also
user-configurable via tessellation control and evaulation
shaders, which we'll get into before long. As such, they don't
have a defined provoking vertex.  The number of primitives
produced with this topology is equal to the number of vertices
divided by
[`patchControlPoints`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineTessellationStateCreateInfo.html#_members).

#### Primitive assembly restart

The only other field of note in
[`VkPipelineInputAssemblyStateCreateInfo`](https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkPipelineInputAssemblyStateCreateInfo.html)
is <code><a
href="https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkBool32.html">VkBool32</a>
primitiveRestartEnable</code>. If this is set to `VkTrue`, you're
performing an indexed draw, and you're using one of the "strip"
or "fan" topologies, a special vertex index of "all 1s" (e.g.
`0xFFFF` for `uint16_t` indices) will cause primitive assembly to
restart. This discards any of the last few vertices that aren't
yet part of a primitive, and then starts the primitive assembly
over from the immediately following index and continues onwards
from there. The last index for the draw call stays the same. This
"all 1s" value is checked for before `vertexOffset` is added to
the index.

You're actually only allowed to set `primitiveRestartEnable` to
`VkTrue` at all if you're using one of the "strip" or "fan"
topologies; setting it to `VkTrue` under other circumstances will
provoke a Vulkan error.

As you can imagine, this could come in handy if you're modeling
something that is easily represented by a series of discontinuous
triangle strips or fans, like a large flat sheet or a gemstone,
as it helps to cut down on redundant vertices. In practice,
though, you'll probably end up just using a triangle list in this
day and age if you're not porting an older application to Vulkan.

### Vertex shading

After primitive assembly, the vertices are passed to the vertex
shading stage. One vertex shader invocation is produced for each
vertex in each instance in the draw call. Although primitive
assembly technically takes place before vertex shading, its
results are not particularly apparent in the vertex shader, so
it's relatively safe to imagine it happening afterwards if you
want. What _is_ apparent in the vertex shader is the vertex index
and instance index for the vertex associated with the invocation,
as we've already discussed:

```glsl
in int gl_BaseVertex;    // the starting vertex index
in int gl_BaseInstance;  // the starting instance index
in int gl_VertexIndex;   // the current vertex index
in int gl_InstanceIndex; // the current instance index
```

See "Vertices and instances" if you need a deeper refresher on
these built-in inputs.

If you're not using tessellation or geometry shading, the vertex
shader is where you prepare your vertices for rasterization. This
is done using the built-in `out gl_PerVertex` block. This block
is also present in the other pre-rasterization shading stages,
though, so we'll discuss it in its own section.

### The per-vertex blocks

The following output block is pre-declared in vertex,
tessellation control, tessellation evaluation, and geometry
shaders, as an array `gl_out[]` in the tessellation control case:

```glsl
out gl_PerVertex {
    vec4  gl_Position;
    float gl_PointSize;
    float gl_ClipDistance;
    float gl_CullDistance;
};
```

Similarly, the following input block array is pre-declared in
tessellation control, tessellation evaluation, and geometry
shaders:

```glsl
in gl_PerVertex {
    vec4  gl_Position;
    float gl_PointSize;
    float gl_ClipDistance;
    float gl_CullDistance;
} gl_in[];
```

We'll discuss the (very minor) differences between the
`gl_PerVertex` blocks in different shader stages in their
respective sections; the purpose of this section is to explore
the meaning of the different variables within the block, which
are always the same. These variables are involved in configuring
rasterization prior to fragment shading.

They can be written to from any of the types of shaders in which
they are pre-declared. If any one of them hasn't been written in
an earlier stage, it will be undefined at the outset of the
following stage. Otherwise, the values written by prior stages
will be legible to later ones.

If you have experience with OpenGL, you probably already know
what these variables do. Their meaning in Vulkan is essentially
the same as in OpenGL. As such, you can safely skip this section
if you're confident in your understanding of the `gl_PerVertex`
block; we'll cover the host-side aspects of configuring
rasterization when we focus on rasterization directly. The rest
of this section will assume you have little to no familiarity
with these variables or the concepts behind them.

#### `vec4 gl_Position`

This is intended for writing the coordinates of the vertex in
_clip space_, which is one of the coordinate systems used in
Vulkan. Getting your vertices into clip space properly usually
involves a series of _linear transformations_. Also, clip space
works in _homogenous coordinates_, which is why `gl_Position` is
a `vec4` despite being intended to represent a coordinate in "3D"
space. All of these concepts may be new to you, and each of them
has a fair amount of depth even just in this context, so we'll
take each one in turn.

##### Homogeneous coordinates

Homogeneous coordinates are not specifically a computer graphics
concept at all, but rather are a general mathematical tool used
in _projective geometry_, a branch of mathematics that studies
the geometry of projections (as you might imagine :P). They were
first introduced by August Möbius (of Möbius strip fame) in his
1827 book [_Der Barycentrische
Calcul_](http://sites.mathdoc.fr/cgi-bin/oeitem?id=OE_MOBIUS__1_1_0),
named for the [barycentric
coordinates](https://en.wikipedia.org/wiki/Barycentric_coordinate_system)
he describes therein. Homogeneous coordinates are relatively
similar to the Cartesian coordinates you probably encountered in
grade school, but they allow for points at infinity; barycentric
coordinates are a special case in which coordinates are given in
relation to a [simplex](https://en.wikipedia.org/wiki/Simplex).

The most obvious motivation for homogeneous coordinates is
expressed in a picture like this one, which you've probably
encountered the likes of before in the context of discussions
about projection:

![train tracks vanishing at horizon](pics/tracks_persp.svg)

As you can see, the train tracks appear to meet at a point on the
horizon. If you imagine yourself standing here and looking down
at your feet, you could easily see that the tracks were parallel,
but they don't appear that way anymore when you look forward like
this. How could we express this situation mathematically?

In a Euclidean space—like the kind of geometry you probably did
in grade school—parallel lines never converge like they do in the
picture. That what it means for two lines to be parallel, right?
They never intersect? Well, if you look at those train tracks, it
appears that they _do_ intersect, somewhere out there over the
rainbow.

Of course, if you actually started walking towards where this
point appears to be, it would never get any closer, even if the
train tracks were infinitely long. The tracks would always appear
parallel if you looked straight down at them. So, it might be
natural to say that they intersect "at infinity."

If we wanted to approach this idea analytically—i.e., using
algebra—Cartesian coordinates wouldn't exactly be ideal.
Cartesian coordinates are that classic kind where a 2D point is
described by two numbers (_x_,_y_):

![points on cartesian grid](pics/cartesian_points.svg)

This works great for a Euclidean space, but we don't have any
straightforward way of expressing a point "at infinity" where our
train tracks could intersect. Homogeneous coordinates solve this
problem by using an extra number _w_ to describe a point in
addition to the familiar numbers from Cartesian coordinates—so
instead of (_x,y_), we have (_x,y,w_):

![points on homogeneous cartesian grid](pics/homogeneous_points.svg)

Here are our points from before expressed in homogeneous
coordinates. In this diagram, every point has a _w_ component of
1. Homogeneous coordinates can describe Euclidean space just
fine—this is like the situation where you're looking straight
down at the train tracks. What if we were to look up slightly?

![points on slight homogeneous grid](pics/homogeneous_grid_slight.svg)

Here we've decided to say that points on the _x_-axis from before
have a _w_ component of 1. As you can see, points with a _w_
component of less than 1 appear further away than the _x_-axis,
whereas points with a _w_ component of more than 1 appear closer
than it.

A

A

A

A

A

A

A

A

A

A

