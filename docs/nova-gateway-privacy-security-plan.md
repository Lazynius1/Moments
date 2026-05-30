# Nova Gateway Privacy and Security Plan

## Goal
Define the privacy and security guardrails for a future backend-powered Nova so that moving orchestration to the cloud improves control without creating unnecessary data exposure.

## Core Principle
Nova Gateway should follow `minimum necessary data` at every layer:
- send less
- store less
- retain less
- log less
- expose less

Power is not the goal by itself. Control, isolation, and user trust are.

## Threat Model

### Main Risks
- sending too much user context to backend unnecessarily
- retaining prompts or outputs longer than needed
- mixing user data across requests or caches
- allowing tool actions without strong authorization checks
- leaking model credentials or privileged backend tokens
- logging sensitive content in plain text
- caching highly personal context without separation rules

### Sensitive Data Types
For Nova, sensitive data may include:
- identity details
- relationship details
- personal preferences
- private profile settings
- unpublished content
- private stories / moments
- conversation history
- any attached media

## Privacy Architecture

### Client Responsibilities
The iOS app should only send:
- the new user message
- the current conversationId
- the minimum attachment references or media payload needed for the task
- locale and lightweight UX metadata if needed

The client should not send:
- the entire long conversation every turn unless absolutely necessary
- unnecessary full user documents
- unrelated profile or social data
- raw app state that Nova does not need

### Gateway Responsibilities
The gateway should:
- verify Firebase auth server-side
- load only the user-scoped data needed for the turn
- assemble prompt context on demand
- keep secrets and model credentials server-side only
- apply tool authorization before every read or write

### Data Sources
Backend access should remain scoped to:
- `users/{userId}/novaConversations/{conversationId}`
- `users/{userId}/novaMemory/memory`
- `users/{userId}/novaMemory/context`
- the exact Moments collections required by each tool

## Memory Policy

### Saved Memory
Saved memory should contain only durable, reusable facts such as:
- preferred name
- explicitly stated pronouns
- stable preferences
- recurring goals
- important relationships
- stable Moments usage preferences

### Conversation History Memory
Conversation continuity should contain:
- short rolling summaries
- open topics
- unresolved decisions

### Do Not Store
Nova should avoid storing:
- one-off moods
- failed actions
- temporary requests
- speculative assumptions
- sensitive identifiers unless there is a strong product reason
- raw attachments in memory

### User Control
Users should be able to:
- inspect saved memory
- delete individual memory facts
- clear all saved memory
- clear continuity summaries
- disable memory features if product design later allows it

## Logging Policy

### Default Rule
Do not log full prompts or full model responses unless there is a strong operational need and explicit handling policy.

### Safe Telemetry
Prefer logging:
- request ids
- user-scoped anonymous identifiers if possible
- token counts
- cache hits / misses
- latency
- tool names
- error codes

### Restricted Logging
If richer logs are needed for debugging:
- gate them behind an explicit debug mode
- redact known sensitive fields
- avoid long-term retention
- keep access limited to trusted operators

## Retention Policy

### Conversations
Conversation storage should be retained only as long as the product needs it.

### Saved Memory
Saved memory may persist longer than conversation history, but it should remain:
- editable
- deletable
- minimal

### Continuity Summaries
Continuity summaries should be:
- short
- capped in count
- replaceable
- removable when memory is cleared

### Operational Logs
Operational logs should have explicit retention windows. Avoid indefinite storage of Nova request content.

## Tool Security

### Read Tools
Every read tool must verify:
- authenticated user identity
- user-scoped access to the requested resource
- no access to unrelated user-private data

### Write Tools
Every write tool must require:
- authenticated user identity
- tool-specific authorization
- explicit in-app confirmation where relevant
- clear success/failure handling

Nova must never claim a write succeeded unless the backend tool result confirms success.

## Auth and Identity

### Required Pattern
Every request to Nova Gateway should:
1. carry a Firebase ID token
2. be verified server-side
3. derive the effective `userId` from the verified token

Never trust a raw client-provided `userId` without verification.

### Service-to-Service Access
Backend access to Gemini / Vertex / Firestore should use server-side credentials only.

## Caching Safety

### What Can Be Cached
Safe candidates:
- Nova system prompt
- Moments app instruction blocks
- tool schemas
- generalized stable context blocks

### What Should Be Treated Carefully
Potentially cacheable but user-sensitive:
- user stable memory snapshot
- profile interpretation blocks

If user-scoped memory is cached, it must remain isolated per user and never be reused across users.

### What Should Not Be Cached Broadly
- raw latest messages
- sensitive write payloads
- ephemeral private activity details
- mixed multi-user private context

## Media Handling

### Attachments
If Nova receives media:
- use temporary references when possible
- avoid retaining raw uploaded media longer than needed for the turn
- do not silently move user media into long-lived analysis stores

### Analysis Results
If media is analyzed, only store compact derived context when product value clearly justifies it.

## Operational Safeguards

### Rate Limiting
Add:
- per-user request rate limits
- abuse protection
- cost anomaly detection

### Cost Protection
Add:
- max request size
- max context size
- max tool chain length
- optional per-user daily budget alerts

### Failure Modes
If the gateway fails:
- return a graceful Nova error
- do not expose internal stack traces to the client
- avoid partial writes when actions fail

## Compliance-Oriented Practices

Even without targeting a formal compliance regime first, Nova Gateway should adopt:
- least privilege
- data minimization
- retention limits
- deletion pathways
- auditability of write actions

## Recommended Implementation Order
1. auth verification
2. minimal logging
3. scoped data loading
4. write confirmation enforcement
5. memory governance
6. retention policies
7. caching with user isolation rules

## Product Positioning
Moving Nova to the cloud is not automatically worse for privacy.

It can be better if we use the gateway to enforce:
- stricter auth
- smaller data flow
- cleaner logging
- stronger tool controls
- better deletion behavior

The goal is not "Nova knows more".
The goal is "Nova is smarter with less unnecessary exposure".
