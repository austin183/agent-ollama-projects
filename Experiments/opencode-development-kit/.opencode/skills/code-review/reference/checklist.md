# Code Review Checklist

## Contents
- Design evaluation
- Functionality verification
- Test coverage
- Style compliance
- Documentation

## Design Evaluation

### Architecture
- [ ] Change fits existing architecture
- [ ] New modules/libraries are justified
- [ ] No unnecessary complexity or over-engineering
- [ ] SOLID principles followed

### Separation of Concerns
- [ ] Business logic separated from infrastructure
- [ ] UI layer doesn't contain business rules
- [ ] Database queries in repository/DAO, not controllers
- [ ] Configuration in files/environment, not code

## Functionality Verification

### Core Logic
- [ ] Code handles expected inputs correctly
- [ ] Edge cases considered and handled
- [ ] Concurrency/safety issues addressed
- [ ] Error conditions properly handled

### Testing
- [ ] New tests added for new functionality
- [ ] Tests cover edge cases
- [ ] Tests are isolated and deterministic
- [ ] Mock dependencies are appropriate

## Test Coverage

### Unit Tests
- [ ] Functions tested in isolation
- [ ] Boundary conditions covered
- [ ] Error paths tested

### Integration Tests
- [ ] Component interactions verified
- [ ] External dependencies mocked appropriately
- [ ] Test order doesn't matter

## Style Compliance

### Linter Status
- [ ] Linter passes with no errors
- [ ] Type checker passes (if applicable)

### Style Guide
- [ ] Naming follows project conventions
- [ ] Formatting matches surrounding code
- [ ] Only style issues marked with `Nit:` are suggestions

## Documentation

### Code Comments
- [ ] Comments explain *why*, not *what*
- [ ] Complex algorithms have explanations
- [ ] TODOs have issue references

### Public APIs
- [ ] Function signatures documented
- [ ] Parameters and return values described
- [ ] Exceptions documented

### Changes
- [ ] README updated if needed
- [ ] API documentation updated
- [ ] Configuration changes documented

## Nit Comments (Optional Polish)

Prefix non-critical suggestions with `Nit:`

- [ ] Variable naming could be clearer
- [ ] Minor refactoring opportunity
- [ ] Formatting preference
- [ ] Code organization suggestion

## Approval Criteria

### Approve When
- [ ] All critical checklist items pass
- [ ] Design is sound and maintainable
- [ ] Tests cover important scenarios
- [ ] No blocking issues remain

### Request Changes When
- [ ] Major design flaws exist
- [ ] SOLID principles violated
- [ ] Tests missing for new functionality
- [ ] Documentation incomplete
