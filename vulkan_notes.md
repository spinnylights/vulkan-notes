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
control over.  The explicitness is perhaps not so much in the
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
   drawing commands to, allocate memory with, etc.  In order to
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
   processing.  Swapchains facilitate synchronization with the
   refresh rate of the display, and can be used to implement
   techniques like double and triple buffering.

   A swapchain will need to be set up at least once, but can be
   long-lived under some circumstances.  However, because it is
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

Vulkan pipelines represent a set of operations for the GPU to
perform. They come in three variants: _graphics_, _compute_, and
_ray tracing_.  They are where you attach your shaders, and where
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
cover separately. However, they also have aspects in common.  For
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
even if the CPU code is properly multithreaded.  Furthermore, the
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
of light as they travel through a scene's geometry.  They are
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

## GLSL

This is a detailed discussion of the [OpenGL Shading
Language](https://www.khronos.org/opengl/wiki/OpenGL_Shading_Language),
or GLSL, from the perspective of use with Vulkan. It does not
assume prior graphics programming experience, although it does
assume knowledge of C and C++. In addition to [the GLSL
spec](https://www.khronos.org/registry/OpenGL/specs/gl/GLSLangSpec.4.60.pdf),
it interleaves information from the Vulkan spec, the [GLSL Vulkan
extension
spec](https://github.com/KhronosGroup/GLSL/blob/master/extensions/khr/GL_KHR_vulkan_glsl.txt),
and the [OpenGL
spec](https://www.khronos.org/registry/OpenGL/specs/gl/glspec46.core.pdf).

GLSL largely resembles a simplified version of C. The rules for
declaring variables, defining functions, etc. are mostly the
same, although it lacks pointers. However, it has stronger
support for graphics-specific types and operations, as you might
expect.

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

## Shaders

A shader is a computer program written in a shading language,
which is a programming language used to write shaders.
Tautological? You betcha. It's hard to give a rigorous definition
of the term "shader" these days because although shaders usually
run on GPUs, they don't have to, and although they're often used
in the production of visual imagery, they aren't always. One
thing that does stand out about them is that they're generally
parallel by default; they're intended to be run with many
invocations operating at once, and synchronization between these
invocations is the programmer's responsibility. Shading languages
also tend to include more built-in support for linear algebra
than other kinds of programming langauges, and they tend to be
C-like.

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
