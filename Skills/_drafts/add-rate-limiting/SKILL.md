---
name: add-rate-limiting
description: Use this when implementing rate limiting for API endpoints.
---

## When to use
Use this skill when you need to implement rate limiting on an API endpoint to prevent abuse and ensure fair usage among users.

## Procedure
1. **Identify the Endpoint**: Determine which API endpoint requires rate limiting (e.g., login endpoint).
2. **Choose a Rate Limiting Strategy**: Decide on a strategy (e.g., fixed window, sliding window, token bucket) based on your application's needs.
3. **Set Rate Limits**: Define the maximum number of requests allowed per user within a specified time frame (e.g., 5 login attempts per minute).
4. **Implement Middleware**: Integrate rate limiting middleware into your application. For example, if using Express.js, you can use libraries like `express-rate-limit`.
5. **Configure Middleware**: Set up the middleware with the defined rate limits and apply it to the login route.
6. **Handle Rate Limit Exceeded**: Implement logic to return an appropriate response (e.g., HTTP 429 Too Many Requests) when the rate limit is exceeded.
7. **Test the Implementation**: Conduct tests to ensure that the rate limiting works as expected and does not interfere with legitimate users.
8. **Monitor and Adjust**: After deployment, monitor the usage and adjust the rate limits as necessary based on user behavior and feedback.
