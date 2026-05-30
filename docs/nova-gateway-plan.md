# Nova Gateway Plan

## Goal
Move Nova from a mostly client-side assistant to a `thin iOS client + backend gateway` architecture so we can:
- reduce cost
- offload heavy orchestration from the app
- enable real Gemini/Vertex caching in a future phase
- improve memory consistency, tool orchestration, and observability

## Current Constraint
Nova currently uses Firebase AI Logic / FirebaseAI on-device. That stack does not currently support context caching, so real prompt caching would require moving the heavy LLM orchestration to backend infrastructure.

## Target Architecture

### iOS Client
The app should stay responsible for:
- chat UI
- streaming UX
- image attachment flow
- action confirmation overlays
- navigation and Moments-native interactions
- local optimistic states where useful

The app should stop being responsible for:
- assembling large prompts
- heavy tool orchestration
- persistent memory policy
- long prompt context reuse logic

### Nova Gateway
The backend should become responsible for:
- verifying Firebase auth
- loading user-scoped Nova memory and conversation context
- assembling the full prompt and tool schema
- selecting and calling Gemini / Vertex
- performing tool orchestration
- writing durable memory updates
- managing cacheable stable context blocks
- emitting usage and cost telemetry

### Data Layer
Firestore remains the source of truth for:
- `users/{userId}/novaConversations/{conversationId}`
- `users/{userId}/novaMemory/memory`
- `users/{userId}/novaMemory/context`
- relevant Moments app data used by Nova tools

## Phase 1: Minimal Gateway

### Objective
Introduce a backend entrypoint without breaking the current Nova UX.

### Work
1. Create a `POST /nova/chat` endpoint.
2. Accept:
   - `conversationId`
   - `message`
   - `attachments`
   - `locale`
3. Verify the Firebase Auth token on every request.
4. Load:
   - user memory
   - conversation summaries
   - stable app context
5. Build the Nova prompt server-side.
6. Call Gemini / Vertex from the backend.
7. Return:
   - assistant text
   - tool actions if needed
   - memory/context updates if needed

### Success Criteria
- The app no longer assembles the heavy prompt.
- The backend can generate equivalent or better Nova responses.
- Existing Nova UI remains unchanged from the user's perspective.

## Phase 2: Memory Model

### Objective
Separate durable saved memory from conversational continuity.

### Saved Memory
Should contain stable reusable user facts such as:
- preferred name
- explicitly stated pronouns
- repeated likes/dislikes
- goals
- important relationships
- stable Moments preferences

### History Memory
Should contain:
- recent conversation summaries
- open threads
- unresolved questions
- continuity context from prior Nova chats

### Do Not Save
- one-off requests
- temporary moods unless repeated over time
- failed publish attempts
- speculative guesses
- sensitive details without a clear product need

### Success Criteria
- Nova remembers useful stable facts without needing explicit "remember this".
- Nova still supports explicit memory writes for user-controlled recall.
- Users retain the ability to inspect and clear memory.

## Phase 3: Tool Orchestration in Backend

### Objective
Move Nova's heavy agent logic to the gateway.

### Responsibilities
The backend should decide:
- whether a tool is needed
- whether to ask a clarifying question
- whether a write action needs confirmation
- whether memory should be updated

### Tool Rules
- Read tools can run automatically when useful.
- Write tools always require explicit in-app confirmation.
- Nova must never claim success unless the tool returns success.

### Priority Tool Families
- profile snapshot
- recent moments
- recent stories
- privacy settings
- followers / following / mutuals
- bio / website
- active hours
- notification preferences
- follow request
- create moment

## Phase 4: Context Caching

### Objective
Introduce stable prompt caching through Gemini API / Vertex AI.

### Cacheable Stable Blocks
- Nova system prompt
- Moments app context
- tool definitions
- stable user memory snapshot
- optionally some slowly changing profile context

### Non-Cacheable Dynamic Blocks
- latest user message
- fresh tool results
- rapidly changing activity context
- write confirmations
- live turn state

### Strategy
1. Build a stable prompt prefix.
2. Cache that prefix using Gemini / Vertex caching support.
3. Add only dynamic context per request.
4. Track cache hit / miss behavior and effective savings.

### Expected Benefit
- lower token cost on repeated prompts
- less repeated transmission of static Nova context
- cleaner app runtime behavior

## Phase 5: Observability and Cost Control

### Metrics
Track:
- input tokens
- output tokens
- latency
- tool usage
- memory writes
- cache hits / misses
- estimated cost per turn

### Dashboards
Useful rollups:
- cost per active Nova user
- cost per conversation
- cache savings over time
- tool call frequency
- failed action rate

### Success Criteria
- We can measure whether gateway Nova is cheaper than client-heavy Nova.
- We can identify which context blocks are worth caching.

## Phase 6: Security

### Requirements
- Verify Firebase ID token server-side.
- Never trust raw `userId` from the client.
- Keep model credentials fully off-device.
- Restrict every read/write tool to the authenticated user scope.
- Keep write actions behind explicit confirmation.

### Privacy
- Store only the minimum useful memory.
- Avoid saving unnecessary sensitive details.
- Keep memory clearing and inspection available to the user.

## Phase 7: Rollout

### Migration Strategy
Use a feature flag and migrate in stages:
1. backend generation only
2. backend prompt assembly and memory loading
3. backend tool orchestration
4. backend memory writes
5. caching

### Fallback
Keep a temporary fallback path so Nova can still respond if the gateway fails during rollout.

### Success Criteria
- No hard UX regression during migration.
- Nova responses remain at least as good as the current implementation.
- Backend path becomes the default once stable.

## Suggested Endpoints
- `POST /nova/chat`
- `POST /nova/tool/confirm`
- `GET /nova/conversation/:id`
- `GET /nova/memory`
- `DELETE /nova/memory`
- `GET /nova/health`

## Recommended Implementation Order
1. minimal Nova Gateway
2. server-side prompt assembly
3. server-side Gemini / Vertex call
4. server-side tool orchestration
5. memory refinement
6. caching
7. telemetry and optimization

## Notes
- The current Nova implementation is already much closer to the right product shape.
- The gateway is the next major architecture step, not a prerequisite for the current Nova to work well.
- This plan is intended as the roadmap for a future `Nova Phase 2`.
