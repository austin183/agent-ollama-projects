# Research into Existing Website

```
We are working on gathering information to work on @_agent_docs/InitialThoughts.md. Can you please do some research into the website in @/Users/austin/workspace/austin183.github.io/MidiSongBuilder/Midiestro3D.html and the libraries it uses and how they could be reused to work on the project as it relates to the application in @/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker? Please write your findings to a new document in @_agent_docs/research/. Specifications for the website are available in @_agent_docs/specifications/world-view-specifications.md.
```

# Planning

## Replacement prompts with plan-bdd agent
- "Specify behavior and plan implementation based on [specs]. Write to _agent_docs/plans/."
- "Add Given-When-Then scenarios for section [X.Y] in [plan file]."
- "Create a plan for the change requests in [path]. Include test scenarios for each phase."
- "Please create a plan for the changes requested in the review at [path]. Include test scenarios for each phase."

# Regular Planning
```
Now that we have all the specifications in @_agent_docs/specifications/world-view-specifications.md and research in @_agent_docs/research/, we need to come up with a plan to implement the collage maker website in @/Users/austin/workspace/austin183.github.io based on the macOS project in @/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker. Please review the documentation and help me write up a plan in phases to a new document in @_agent_docs/plans/. If you have any open questions, please include them in a section in the plan document. We have the @planner agent that can help.
```

# Test Planning
```
Let's draft a test plan for Section 3.4 in @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/plans/2026-07-02-midpoint-gap-phase4-priority-plan.md and pair with the @planner and @world-review subagents for additional considerations for coverage.  We can use @/Users/austin/workspace/References/claude-plugins/humanlayer/commands/iterate_plan.md for guidance on how to update the existing @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/plans/2026-07-02-midpoint-gap-phase4-priority-plan.md file in the 3.3 section with the test scenarios we want to cover with the impelementation.  We can review the plan to understand the request, call @world-review to get its perspective, and then call @planner with both the context and perspective to plan out the tests.  Then we can iterate the section of the plan from there.
```

# Change Request Planning
```
We need to create a plan for the change requests in @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/specifications/change-requests .  We can use our /writing-plans skill for guidance.  Please also include a Test Plan for each Phase of work.  We can call @world-review to get its perspective, and then call @planner with both the context and perspective to plan out the phases tests.  Please write the new plan to @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/plans
```

# Implementation
## Implement code from a plan
```
Please implement Section 3.6 in @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/plans/2026-07-02-midpoint-gap-phase4-priority-plan.md using our /building-web-apps skill for guidance.  Then run @world-review and address any concerns.  Then please update our project timeline and use the /capturing-learnings and add any new learnings to a new document in @_agent_docs/learnings . Please use your best judgement on what was relevant to learn compared to what we already know from our existing skills.  Please do not ask me what was important.  I am only partially paying attention.  If nothing stood out as relevant, or we already have it covered, making no updates is an acceptable outcome of this exercise.
```
## Implement tests from a plan
```
Please implement the tests in Section 3.6 in @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/plans/2026-07-02-midpoint-gap-phase4-priority-plan.md using our /building-web-apps skill for guidance.  Then run @world-review and address any concerns.  Then please update our project timeline and use the /capturing-learnings and add any new learnings to a new document in @_agent_docs/learnings . Please use your best judgement on what was relevant to learn compared to what we already know from our existing skills.  Please do not ask me what was important.  I am only partially paying attention.  If nothing stood out as relevant, or we already have it covered, making no updates is an acceptable outcome of this exercise.
```

# Updates
```
Please update our project timeline and use the /capturing-learnings and add any new learnings to a new document in @_agent_docs/learnings . Please use your best judgement on what was relevant to learn compared to what we already know from our existing skills.  Please do not ask me what was important.  I wasn't paying attention.  If nothing stood out as relevant, or we already have it covered, making no updates is an acceptable outcome of this exercise.
```

## Apply Learnings to Skills
```
Please use the learnings in @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/learnings/2026-07-04-title-renderer-test-refinement.md to refine our building-web-apps skill using /skills-best-practice for guidance.
```

## Skill Housekeeping
```
/skills-best-practice Please review our building-web-apps skills for best practices and organizational consistency
```

# Code Review
```
/code-review Please review our web project in @/Users/austin/workspace/austin183.github.io/CollageMaker with specific focus on the files we have staged to commit, but please include the whole project as context around the changes.  Please write your review to @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/reviews .  The changes are based on the plan in @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/plans/2026-07-17-title-changes-implementation.md .   Please review the code and then get a perspective from @world-review to add to your own review findings for the changes and write the final review.
```

alternative multi-perspective review
for each model, starting with qwen 27b, then world agent, then gemma 31b
```
/review Staged Changed please and write your pre-merge-review to /Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/specifications/change-requests with a suffix of tony along side peter's review in the same folder.  During your analysis, please try to find additional concerns rather than repeating peter's or hugo's and validate the concerns raised by peter and hugo in their reviews.
```

then with qwen 27b

```
Can you please analyze the reviews from @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/specifications/change-requests/2026-07-12-pre-merge-review-hugo.md @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/specifications/change-requests/2026-07-12-pre-merge-review-peter.md and @/Users/austin/workspace/austin183.github.io/CollageMaker/_agent_docs/specifications/change-requests/2026-07-12-pre-merge-review-tony.md and confirm the findings from each and write a pre-merge-review-final version that contains the confirmed concerns and recommendations to the same folder for us to work on?
```