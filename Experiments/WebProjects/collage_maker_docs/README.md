# What is this?
This folder contains a snapshot of the _agent_docs folder from the project at https://github.com/austin183/austin183.github.io for the CollageMaker web app.  It includes the documentation gathered while developing the web app.

# Why is it here? 
I did not want to bloat the website https://austin183.github.io/ with these files, so they live here now.  It may become stale since I copied it from an ignored folder in the git project, but this is before the first merge to main, so it feels like a good place to snap the shot.

# Why do I care to read it?
You don't.  I don't.  However, there could be good slop in here to feed to an LLM on how to approach a software development project.

# What are some highlights?
## Learnings and Skill Building
Based on https://safetyculture.com/topics/kaizen-continuous-improvement/improvement-kata , the idea is that the agent can build its own learnings through practice and apply them to skills so the agent builds up good practices based on the projects it works on.  The learnings folder is full of what the agent learned while working on the project.

## Behavioral Driven Development Planning
BDD was introduced almost at the end of development.  Planning feels like the right time to get the definitions for how the user interacts with the application defined so the agent does not have to make it up on the spot.

## SOLID Reviewing
Reviews made use of the world agent to catch theoretical issues while SOLID review skills were used to make sure the project was in a maintainable state as features were added.  This kept the project from tipping over at any point based on my patchwork change request style.  

## Project Timeline
The agents were told to write out summaries of their sessions to help with LLM Usage analysis.  This practice also gives agents historical context that can get lost between sessions, costing repetitive discovery and context building tokens that can be better spent pushing the timeline forward.

## Prompts and Next Prompts
I collect reusable prompts and then order them based on plans and change requests.  That way when it comes time to start new sessions, I can view the results of the previous session, fill in the right blanks in the right prompts, and copy paste them into the right agent for the next session to start.  It's just automated enough without being detrimentally automated.  Like the difference between laying down tracks and riding in a train and riding in a car with fully autonomous driving.  It took a bit of time to get it set up where I want to go, and sometimes I have to wait for a departure or arrival, but I can read a book or walk my dog without worrying about a butterfly sending me over a cliff.