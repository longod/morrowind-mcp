---@meta
-----@diagnostic disable: duplicate-doc-field, duplicate-doc-alias

--- MCP schema annotations
--- https://modelcontextprotocol.io/specification/2025-11-25/schema

-- ============================================================================
-- JSON-RPC
-- ============================================================================

---@alias MCP.RequestId string|number
---@alias MCP.ProgressToken string|number
---@alias MCP.JsonValue any
---@alias MCP.AnyMap table<string, MCP.JsonValue>
---@alias MCP.StringMap table<string, string>
---@alias MCP.PrimitiveValue string|number|boolean|string[]
---@alias MCP.PrimitiveValueMap table<string, MCP.PrimitiveValue>

---@enum MCP.Method
local method = {
    completion_complete = "completion/complete",
    elicitation_create = "elicitation/create",
    initialize = "initialize",
    logging_setlevel = "logging/setLevel",
    notifications_cancelled = "notifications/cancelled",
    notifications_initialized = "notifications/initialized",
    notifications_tasks_status = "notifications/tasks/status",
    notifications_message = "notifications/message",
    notifications_progress = "notifications/progress",
    notifications_prompts_listchanged = "notifications/prompts/list_changed",
    notifications_resources_listchanged = "notifications/resources/list_changed",
    notifications_resources_updated = "notifications/resources/updated",
    notifications_roots_listchanged = "notifications/roots/list_changed",
    notifications_tools_listchanged = "notifications/tools/list_changed",
    notifications_elicitation_complete = "notifications/elicitation/complete",
    ping = "ping",
    tasks_get = "tasks/get",
    tasks_result = "tasks/result",
    tasks_list = "tasks/list",
    tasks_cancel = "tasks/cancel",
    prompts_get = "prompts/get",
    prompts_list = "prompts/list",
    resources_list = "resources/list",
    resources_read = "resources/read",
    resources_subscribe = "resources/subscribe",
    resources_templates_list = "resources/templates/list",
    resources_unsubscribe = "resources/unsubscribe",
    roots_list = "roots/list",
    sampling_createmessage = "sampling/createMessage", -- why camelCase?
    tools_call = "tools/call",
    tools_list = "tools/list",
}

---@alias MCP.Meta table<string, any>

---@class MCP.Result
---@field _meta MCP.Meta?

---@class MCP.Error
---@field code integer
---@field message string
---@field data any?

---@class MCP.JSONRPCRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method MCP.Method
---@field params table<string, any>?

---@class MCP.JSONRPCNotification
---@field jsonrpc "2.0"
---@field method MCP.Method
---@field params table<string, any>?

---@class MCP.JSONRPCResultResponse
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field result MCP.Result

---@class MCP.JSONRPCErrorResponse
---@field jsonrpc "2.0"
---@field id MCP.RequestId?
---@field error MCP.Error

---@alias MCP.JSONRPCResponse MCP.JSONRPCResultResponse|MCP.JSONRPCErrorResponse
---@alias MCP.JSONRPCMessage MCP.JSONRPCRequest|MCP.JSONRPCNotification|MCP.JSONRPCResponse

-- ============================================================================
-- Common
-- ============================================================================

---@alias MCP.Cursor string
---@alias MCP.EmptyResult MCP.Result
---@alias MCP.Role "user"|"assistant"

---@enum MCP.MimeType
local mime_type = {
    image_apng = "image/apng",
    image_avif = "image/avif",
    image_gif = "image/gif",
    image_jpeg = "image/jpeg",
    image_png = "image/png",
    image_svg_xml = "image/svg+xml",
    image_webp = "image/webp",
    audio_aac = "audio/aac",
    audio_flac = "audio/flac",
    audio_mpeg = "audio/mpeg",
    audio_ogg = "audio/ogg",
    audio_wav = "audio/wav",
    text_plain = "text/plain",
    application_json = "application/json",
}

---@enum MCP.LoggingLevel
local logging_level = {
    debug = "debug",
    info = "info",
    notice = "notice",
    warning = "warning",
    error = "error",
    critical = "critical",
    alert = "alert",
    emergency = "emergency",
}

---@class MCP.Annotations
---@field audience MCP.Role[]?
---@field priority number?
---@field lastModified string?

---@class MCP.Icon
---@field src string
---@field mimeType MCP.MimeType?
---@field sizes string[]?
---@field theme "light"|"dark"?

---@class MCP.Implementation
---@field icons MCP.Icon[]?
---@field name string
---@field title string?
---@field version string
---@field description string?
---@field websiteUrl string?

---@class MCP.NotificationParams

---@class MCP.RequestParams
---@field progressToken MCP.ProgressToken?

---@class MCP.PaginatedRequestParams: MCP.RequestParams
---@field cursor MCP.Cursor?

---@class MCP.JsonSchemaObject
---@field ["$schema"] string?
---@field type string
---@field title string?
---@field description string?
---@field properties table<string, MCP.JsonSchemaProperty>?
---@field required string[]?

---@alias MCP.JsonSchemaProperty MCP.StringSchema|MCP.NumberSchema|MCP.BooleanSchema|MCP.EnumSchema|MCP.JsonSchemaObject

-- ============================================================================
-- Content
-- ============================================================================

---@class MCP.TextContent
---@field type "text"
---@field text string
---@field annotations MCP.Annotations?

---@class MCP.ImageContent
---@field type "image"
---@field data string
---@field mimeType MCP.MimeType
---@field annotations MCP.Annotations?

---@class MCP.AudioContent
---@field type "audio"
---@field data string
---@field mimeType MCP.MimeType
---@field annotations MCP.Annotations?

---@class MCP.TextResourceContents
---@field uri string
---@field mimeType MCP.MimeType?
---@field text string

---@class MCP.BlobResourceContents
---@field uri string
---@field mimeType MCP.MimeType?
---@field blob string

---@class MCP.EmbeddedResource
---@field type "resource"
---@field resource MCP.TextResourceContents|MCP.BlobResourceContents
---@field annotations MCP.Annotations?

---@class MCP.ResourceLink
---@field type "resource_link"
---@field icons MCP.Icon[]?
---@field name string
---@field title string?
---@field uri string
---@field description string?
---@field mimeType MCP.MimeType?
---@field annotations MCP.Annotations?
---@field size number?

---@alias MCP.ContentBlock MCP.TextContent|MCP.ImageContent|MCP.AudioContent|MCP.ResourceLink|MCP.EmbeddedResource

-- ============================================================================
-- Completion
-- ============================================================================

---@class MCP.PromptReference
---@field type "ref/prompt"
---@field name string
---@field title string?

---@class MCP.ResourceTemplateReference
---@field type "ref/resource"
---@field uri string

---@alias MCP.CompleteReference MCP.PromptReference|MCP.ResourceTemplateReference

---@class MCP.CompleteArgument
---@field name string
---@field value string

---@class MCP.CompleteContext
---@field arguments MCP.StringMap?

---@class MCP.CompleteRequestParams: MCP.RequestParams
---@field ref MCP.CompleteReference
---@field argument MCP.CompleteArgument
---@field context MCP.CompleteContext?

---@class MCP.CompleteRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "completion/complete"
---@field params MCP.CompleteRequestParams

---@class MCP.CompleteResultCompletion
---@field values string[]
---@field total number?
---@field hasMore boolean?

---@class MCP.CompleteResult: MCP.Result
---@field completion MCP.CompleteResultCompletion

-- ============================================================================
-- Elicitation
-- ============================================================================

---@class MCP.StringSchema
---@field type "string"
---@field title string?
---@field description string?
---@field minLength number?
---@field maxLength number?
---@field format "uri"|"email"|"date"|"date-time"?
---@field default string?

---@class MCP.NumberSchema
---@field type "number"|"integer"
---@field title string?
---@field description string?
---@field minimum number?
---@field maximum number?
---@field default number?

---@class MCP.BooleanSchema
---@field type "boolean"
---@field title string?
---@field description string?
---@field default boolean?

---@class MCP.ConstTitle
---@field const string
---@field title string

---@class MCP.UntitledSingleSelectEnumSchema
---@field type "string"
---@field title string?
---@field description string?
---@field enum string[]
---@field default string?

---@class MCP.TitledSingleSelectEnumSchema
---@field type "string"
---@field title string?
---@field description string?
---@field oneOf MCP.ConstTitle[]
---@field default string?

---@class MCP.LegacyTitledEnumSchema
---@field type "string"
---@field title string?
---@field description string?
---@field enum string[]
---@field enumNames string[]?
---@field default string?

---@class MCP.UntitledMultiSelectEnumSchemaItems
---@field type "string"
---@field enum string[]

---@class MCP.UntitledMultiSelectEnumSchema
---@field type "array"
---@field title string?
---@field description string?
---@field minItems number?
---@field maxItems number?
---@field items MCP.UntitledMultiSelectEnumSchemaItems
---@field default string[]?

---@class MCP.TitledMultiSelectEnumSchemaItems
---@field anyOf MCP.ConstTitle[]

---@class MCP.TitledMultiSelectEnumSchema
---@field type "array"
---@field title string?
---@field description string?
---@field minItems number?
---@field maxItems number?
---@field items MCP.TitledMultiSelectEnumSchemaItems
---@field default string[]?

---@alias MCP.SingleSelectEnumSchema MCP.UntitledSingleSelectEnumSchema|MCP.TitledSingleSelectEnumSchema
---@alias MCP.MultiSelectEnumSchema MCP.UntitledMultiSelectEnumSchema|MCP.TitledMultiSelectEnumSchema
---@alias MCP.EnumSchema MCP.SingleSelectEnumSchema|MCP.MultiSelectEnumSchema|MCP.LegacyTitledEnumSchema
---@alias MCP.PrimitiveSchemaDefinition MCP.StringSchema|MCP.NumberSchema|MCP.BooleanSchema|MCP.EnumSchema

---@class MCP.ElicitRequestFormRequestedSchema
---@field ["$schema"] string?
---@field type "object"
---@field properties table<string, MCP.PrimitiveSchemaDefinition>
---@field required string[]?

---@class MCP.TaskMetadata
---@field ttl number?

---@class MCP.ElicitRequestFormParams: MCP.RequestParams
---@field task MCP.TaskMetadata?
---@field mode "form"?
---@field message string
---@field requestedSchema MCP.ElicitRequestFormRequestedSchema

---@class MCP.ElicitRequestURLParams: MCP.RequestParams
---@field task MCP.TaskMetadata?
---@field mode "url"
---@field message string
---@field elicitationId string
---@field url string

---@alias MCP.ElicitRequestParams MCP.ElicitRequestFormParams|MCP.ElicitRequestURLParams

---@class MCP.ElicitRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "elicitation/create"
---@field params MCP.ElicitRequestParams

---@alias MCP.ElicitAction "accept"|"decline"|"cancel"

---@class MCP.ElicitResult: MCP.Result
---@field action MCP.ElicitAction
---@field content table<string, string|number|boolean|string[]>?

-- ============================================================================
-- Initialize
-- ============================================================================

---@class MCP.ClientRootsCapabilities
---@field listChanged boolean?

---@class MCP.CapabilityMarker

---@class MCP.ClientSamplingContextCapability: MCP.CapabilityMarker
---@class MCP.ClientSamplingToolsCapability: MCP.CapabilityMarker
---@class MCP.ClientElicitationFormCapability: MCP.CapabilityMarker
---@class MCP.ClientElicitationUrlCapability: MCP.CapabilityMarker
---@class MCP.ClientTaskListCapability: MCP.CapabilityMarker
---@class MCP.ClientTaskCancelCapability: MCP.CapabilityMarker
---@class MCP.ClientTaskSamplingCreateMessageCapability: MCP.CapabilityMarker
---@class MCP.ClientTaskElicitationCreateCapability: MCP.CapabilityMarker

---@class MCP.ClientSamplingCapabilities
---@field context MCP.ClientSamplingContextCapability?
---@field tools MCP.ClientSamplingToolsCapability?

---@class MCP.ClientElicitationCapabilities
---@field form MCP.ClientElicitationFormCapability?
---@field url MCP.ClientElicitationUrlCapability?

---@class MCP.ClientTaskSamplingRequestsCapabilities
---@field createMessage MCP.ClientTaskSamplingCreateMessageCapability?

---@class MCP.ClientTaskElicitationRequestsCapabilities
---@field create MCP.ClientTaskElicitationCreateCapability?

---@class MCP.ClientTaskRequestsCapabilities
---@field sampling MCP.ClientTaskSamplingRequestsCapabilities?
---@field elicitation MCP.ClientTaskElicitationRequestsCapabilities?

---@class MCP.ClientTasksCapabilities
---@field list MCP.ClientTaskListCapability?
---@field cancel MCP.ClientTaskCancelCapability?
---@field requests MCP.ClientTaskRequestsCapabilities?

---@class MCP.ServerLoggingCapability: MCP.CapabilityMarker
---@class MCP.ServerCompletionsCapability: MCP.CapabilityMarker
---@class MCP.ServerTaskListCapability: MCP.CapabilityMarker
---@class MCP.ServerTaskCancelCapability: MCP.CapabilityMarker
---@class MCP.ServerTaskToolsCallCapability: MCP.CapabilityMarker

---@class MCP.ClientCapabilities
---@field experimental table<string, MCP.AnyMap>?
---@field roots MCP.ClientRootsCapabilities?
---@field sampling MCP.ClientSamplingCapabilities?
---@field elicitation MCP.ClientElicitationCapabilities?
---@field tasks MCP.ClientTasksCapabilities?

---@class MCP.ServerPromptsCapabilities
---@field listChanged boolean?

---@class MCP.ServerResourcesCapabilities
---@field subscribe boolean?
---@field listChanged boolean?

---@class MCP.ServerToolsCapabilities
---@field listChanged boolean?

---@class MCP.ServerTaskToolsRequestsCapabilities
---@field call MCP.ServerTaskToolsCallCapability?

---@class MCP.ServerTaskRequestsCapabilities
---@field tools MCP.ServerTaskToolsRequestsCapabilities?

---@class MCP.ServerTasksCapabilities
---@field list MCP.ServerTaskListCapability?
---@field cancel MCP.ServerTaskCancelCapability?
---@field requests MCP.ServerTaskRequestsCapabilities?

---@class MCP.ServerCapabilities
---@field experimental table<string, MCP.AnyMap>?
---@field logging MCP.ServerLoggingCapability?
---@field completions MCP.ServerCompletionsCapability?
---@field prompts MCP.ServerPromptsCapabilities?
---@field resources MCP.ServerResourcesCapabilities?
---@field tools MCP.ServerToolsCapabilities?
---@field tasks MCP.ServerTasksCapabilities?

---@class MCP.InitializeRequestParams: MCP.RequestParams
---@field protocolVersion string
---@field capabilities MCP.ClientCapabilities
---@field clientInfo MCP.Implementation

---@class MCP.InitializeRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "initialize"
---@field params MCP.InitializeRequestParams

---@class MCP.InitializeResult: MCP.Result
---@field protocolVersion string
---@field capabilities MCP.ServerCapabilities
---@field serverInfo MCP.Implementation
---@field instructions string?

-- ============================================================================
-- Logging
-- ============================================================================

---@class MCP.SetLevelRequestParams: MCP.RequestParams
---@field level MCP.LoggingLevel

---@class MCP.SetLevelRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "logging/setLevel"
---@field params MCP.SetLevelRequestParams

---@class MCP.LoggingMessageNotificationParams
---@field level MCP.LoggingLevel
---@field logger string?
---@field data MCP.JsonValue

---@class MCP.LoggingMessageNotification
---@field jsonrpc "2.0"
---@field method "notifications/message"
---@field params MCP.LoggingMessageNotificationParams

-- ============================================================================
-- Notifications
-- ============================================================================

---@class MCP.CancelledNotificationParams
---@field requestId MCP.RequestId?
---@field reason string?

---@class MCP.CancelledNotification
---@field jsonrpc "2.0"
---@field method "notifications/cancelled"
---@field params MCP.CancelledNotificationParams

---@class MCP.InitializedNotification
---@field jsonrpc "2.0"
---@field method "notifications/initialized"
---@field params MCP.NotificationParams?

---@class MCP.ProgressNotificationParams
---@field progressToken MCP.ProgressToken
---@field progress number
---@field total number?
---@field message string?

---@class MCP.ProgressNotification
---@field jsonrpc "2.0"
---@field method "notifications/progress"
---@field params MCP.ProgressNotificationParams

---@class MCP.ResourceUpdatedNotificationParams
---@field uri string

---@class MCP.ResourceUpdatedNotification
---@field jsonrpc "2.0"
---@field method "notifications/resources/updated"
---@field params MCP.ResourceUpdatedNotificationParams

---@class MCP.PromptListChangedNotification
---@field jsonrpc "2.0"
---@field method "notifications/prompts/list_changed"
---@field params MCP.NotificationParams?

---@class MCP.ResourceListChangedNotification
---@field jsonrpc "2.0"
---@field method "notifications/resources/list_changed"
---@field params MCP.NotificationParams?

---@class MCP.RootsListChangedNotification
---@field jsonrpc "2.0"
---@field method "notifications/roots/list_changed"
---@field params MCP.NotificationParams?

---@class MCP.ToolListChangedNotification
---@field jsonrpc "2.0"
---@field method "notifications/tools/list_changed"
---@field params MCP.NotificationParams?

---@class MCP.ElicitationCompleteNotificationParams
---@field elicitationId string

---@class MCP.ElicitationCompleteNotification
---@field jsonrpc "2.0"
---@field method "notifications/elicitation/complete"
---@field params MCP.ElicitationCompleteNotificationParams

-- ============================================================================
-- Ping
-- ============================================================================

---@class MCP.PingRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "ping"
---@field params MCP.RequestParams?

-- ============================================================================
-- Tasks
-- ============================================================================

---@alias MCP.TaskStatus "working"|"input_required"|"completed"|"failed"|"cancelled"

---@class MCP.Task
---@field taskId string
---@field status MCP.TaskStatus
---@field statusMessage string?
---@field createdAt string
---@field lastUpdatedAt string
---@field ttl number|nil
---@field pollInterval number?

---@class MCP.CreateTaskResult: MCP.Result
---@field task MCP.Task

---@class MCP.RelatedTaskMetadata
---@field taskId string

---@class MCP.GetTaskRequestParams
---@field taskId string

---@class MCP.GetTaskRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "tasks/get"
---@field params MCP.GetTaskRequestParams

---@class MCP.GetTaskResult: MCP.Result
---@field taskId string
---@field status MCP.TaskStatus
---@field statusMessage string?
---@field createdAt string
---@field lastUpdatedAt string
---@field ttl number|nil
---@field pollInterval number?

---@class MCP.GetTaskPayloadRequestParams
---@field taskId string

---@class MCP.GetTaskPayloadRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "tasks/result"
---@field params MCP.GetTaskPayloadRequestParams

---@class MCP.GetTaskPayloadResult: MCP.Result

---@class MCP.ListTasksRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "tasks/list"
---@field params MCP.PaginatedRequestParams?

---@class MCP.ListTasksResult: MCP.Result
---@field nextCursor string?
---@field tasks MCP.Task[]

---@class MCP.CancelTaskRequestParams
---@field taskId string

---@class MCP.CancelTaskRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "tasks/cancel"
---@field params MCP.CancelTaskRequestParams

---@class MCP.CancelTaskResult: MCP.Result
---@field taskId string
---@field status MCP.TaskStatus
---@field statusMessage string?
---@field createdAt string
---@field lastUpdatedAt string
---@field ttl number|nil
---@field pollInterval number?

---@class MCP.TaskStatusNotificationParams
---@field taskId string
---@field status MCP.TaskStatus
---@field statusMessage string?
---@field createdAt string
---@field lastUpdatedAt string
---@field ttl number|nil
---@field pollInterval number?

---@class MCP.TaskStatusNotification
---@field jsonrpc "2.0"
---@field method "notifications/tasks/status"
---@field params MCP.TaskStatusNotificationParams

-- ============================================================================
-- Prompts
-- ============================================================================

---@class MCP.PromptArgument
---@field name string
---@field title string?
---@field description string?
---@field required boolean?

---@class MCP.Prompt
---@field icons MCP.Icon[]?
---@field name string
---@field title string?
---@field description string?
---@field arguments MCP.PromptArgument[]?

---@class MCP.ListPromptsRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "prompts/list"
---@field params MCP.PaginatedRequestParams?

---@class MCP.ListPromptsResult: MCP.Result
---@field nextCursor string?
---@field prompts MCP.Prompt[]

---@class MCP.GetPromptRequestParams: MCP.RequestParams
---@field name string
---@field arguments table<string, string>?

---@class MCP.GetPromptRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "prompts/get"
---@field params MCP.GetPromptRequestParams

---@class MCP.PromptMessage
---@field role MCP.Role
---@field content MCP.ContentBlock

---@class MCP.GetPromptResult: MCP.Result
---@field description string?
---@field messages MCP.PromptMessage[]

-- ============================================================================
-- Resources
-- ============================================================================

---@class MCP.Resource
---@field icons MCP.Icon[]?
---@field name string
---@field title string?
---@field uri string
---@field description string?
---@field mimeType MCP.MimeType?
---@field annotations MCP.Annotations?
---@field size number?

---@class MCP.ListResourcesRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "resources/list"
---@field params MCP.PaginatedRequestParams?

---@class MCP.ListResourcesResult: MCP.Result
---@field nextCursor string?
---@field resources MCP.Resource[]

---@class MCP.ReadResourceRequestParams: MCP.RequestParams
---@field uri string

---@class MCP.ReadResourceRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "resources/read"
---@field params MCP.ReadResourceRequestParams

---@class MCP.ReadResourceResult: MCP.Result
---@field contents (MCP.TextResourceContents|MCP.BlobResourceContents)[]

---@class MCP.SubscribeRequestParams: MCP.RequestParams
---@field uri string

---@class MCP.SubscribeRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "resources/subscribe"
---@field params MCP.SubscribeRequestParams

---@class MCP.UnsubscribeRequestParams: MCP.RequestParams
---@field uri string

---@class MCP.UnsubscribeRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "resources/unsubscribe"
---@field params MCP.UnsubscribeRequestParams

---@class MCP.ResourceTemplate
---@field icons MCP.Icon[]?
---@field name string
---@field title string?
---@field uriTemplate string
---@field description string?
---@field mimeType MCP.MimeType?
---@field annotations MCP.Annotations?

---@class MCP.ListResourceTemplatesRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "resources/templates/list"
---@field params MCP.PaginatedRequestParams?

---@class MCP.ListResourceTemplatesResult: MCP.Result
---@field nextCursor string?
---@field resourceTemplates MCP.ResourceTemplate[]

-- ============================================================================
-- Roots
-- ============================================================================

---@class MCP.Root
---@field uri string
---@field name string?

---@class MCP.ListRootsRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "roots/list"
---@field params MCP.RequestParams?

---@class MCP.ListRootsResult: MCP.Result
---@field roots MCP.Root[]

-- ============================================================================
-- Sampling
-- ============================================================================

---@class MCP.ModelHint
---@field name string?

---@class MCP.ModelPreferences
---@field hints MCP.ModelHint[]?
---@field costPriority number?
---@field speedPriority number?
---@field intelligencePriority number?

---@alias MCP.IncludeContextMode "none"|"thisServer"|"allServers"

---@class MCP.ToolUseContent
---@field type "tool_use"
---@field id string
---@field name string
---@field input MCP.AnyMap

---@class MCP.ToolResultContent
---@field type "tool_result"
---@field toolUseId string
---@field content MCP.ContentBlock[]
---@field structuredContent MCP.AnyMap?
---@field isError boolean?

---@alias MCP.SamplingMessageContentBlock MCP.TextContent|MCP.ImageContent|MCP.AudioContent|MCP.ToolUseContent|MCP.ToolResultContent

---@class MCP.SamplingMessage
---@field role MCP.Role
---@field content MCP.SamplingMessageContentBlock|MCP.SamplingMessageContentBlock[]

---@alias MCP.ToolChoiceMode "none"|"required"|"auto"

---@class MCP.ToolChoice
---@field mode MCP.ToolChoiceMode?

---@class MCP.CreateMessageRequestParams: MCP.RequestParams
---@field task MCP.TaskMetadata?
---@field messages MCP.SamplingMessage[]
---@field modelPreferences MCP.ModelPreferences?
---@field systemPrompt string?
---@field includeContext MCP.IncludeContextMode?
---@field temperature number?
---@field maxTokens number
---@field stopSequences string[]?
---@field metadata table<string, any>?
---@field tools MCP.Tool[]?
---@field toolChoice MCP.ToolChoice?

---@class MCP.CreateMessageRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "sampling/createMessage"
---@field params MCP.CreateMessageRequestParams

---@class MCP.CreateMessageResult: MCP.Result
---@field model string
---@field stopReason string?
---@field role MCP.Role
---@field content MCP.SamplingMessageContentBlock|MCP.SamplingMessageContentBlock[]

-- ============================================================================
-- Tools
-- ============================================================================

---@class MCP.InputSchema
---@field ["$schema"] string?
---@field type "object"
---@field properties table<string, MCP.JsonSchemaProperty>?
---@field required string[]?
---@field additionalProperties boolean?

---@class MCP.OutputSchema
---@field ["$schema"] string?
---@field type "object"
---@field properties table<string, MCP.JsonSchemaProperty>?
---@field required string[]?

---@alias MCP.ToolTaskSupport "forbidden"|"optional"|"required"

---@class MCP.ToolExecution
---@field taskSupport MCP.ToolTaskSupport?

---@class MCP.ToolAnnotations
---@field title string?
---@field readOnlyHint boolean?
---@field destructiveHint boolean?
---@field idempotentHint boolean?
---@field openWorldHint boolean?

---@class MCP.Tool
---@field icons MCP.Icon[]?
---@field name string
---@field title string?
---@field description string?
---@field inputSchema MCP.InputSchema
---@field execution MCP.ToolExecution?
---@field outputSchema MCP.OutputSchema?
---@field annotations MCP.ToolAnnotations?

---@class MCP.ListToolsRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "tools/list"
---@field params MCP.PaginatedRequestParams?

---@class MCP.ListToolsResult: MCP.Result
---@field nextCursor string?
---@field tools MCP.Tool[]

---@class MCP.CallToolRequestParams: MCP.RequestParams
---@field task MCP.TaskMetadata?
---@field name string
---@field arguments MCP.AnyMap?

---@class MCP.CallToolRequest
---@field jsonrpc "2.0"
---@field id MCP.RequestId
---@field method "tools/call"
---@field params MCP.CallToolRequestParams

---@class MCP.CallToolResult: MCP.Result
---@field content MCP.ContentBlock[]
---@field structuredContent MCP.AnyMap?
---@field isError boolean?

return {
    logging_level = logging_level,
    method = method,
    mime_type = mime_type,
}
