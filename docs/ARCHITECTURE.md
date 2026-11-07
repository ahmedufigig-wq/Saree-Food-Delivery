# Architecture

## Monorepo
- apps/customer_app — Flutter customer app.
- apps/restaurant_portal — restaurant web portal.
- apps/driver_app — Flutter driver app.
- apps/admin_web — administration dashboard.
- apps/marketing_web — official website.
- services/api — Node.js + TypeScript backend.
- packages/shared — shared contracts and utilities.
- infra — deployment and database configuration.

## Backend principles
Clean modular boundaries, RBAC, validation, rate limiting, environment-based configuration, audit-safe logging, and no secrets in source control.

## Core entities
Users, Restaurants, RestaurantCategories, FoodItems, Orders, OrderItems, Addresses, DeliveryDrivers, DriverLocations, Payments, Reviews, Notifications, Cities, Areas, Promotions.
