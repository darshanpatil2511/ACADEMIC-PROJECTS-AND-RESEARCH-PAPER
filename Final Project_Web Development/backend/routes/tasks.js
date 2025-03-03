const express = require("express");
const router = express.Router();
const authenticate = require("../middleware/authenticate");
const Task = require("../models/Task");

// Admin: Create a new task
router.post("/", authenticate, async (req, res) => {
    if (req.user.role !== "admin") {
        return res.status(403).json({ message: "Access Denied: Admins only" });
    }

    const { name, description, dueDate, priority, tags, category } = req.body;

    if (!name || !description || !category) {
        return res.status(400).json({ message: "Task name, description, and category are required" });
    }

    try {
        const task = new Task({
            name,
            description,
            dueDate,
            priority,
            tags,
            category,
            createdBy: req.user.id,
        });
        await task.save();
        res.status(201).json({ message: "Task created successfully", task });
    } catch (err) {
        console.error("Error creating task:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// Get all tasks (Public for TaskList.js)
router.get("/", async (req, res) => {
    try {
        const tasks = await Task.find().populate("assignedTo", "name email");
        res.json(tasks);
    } catch (err) {
        console.error("Error fetching tasks:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// Get task details by ID (Public for TaskDetail.js)
router.get("/:id", async (req, res) => {
    try {
        const task = await Task.findById(req.params.id).populate("assignedTo", "name email");
        if (!task) {
            return res.status(404).json({ message: "Task not found" });
        }
        res.json(task);
    } catch (err) {
        console.error("Error fetching task details:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// Volunteer: Get assigned tasks
router.get("/my-tasks", authenticate, async (req, res) => {
    if (req.user.role !== "volunteer") {
        return res.status(403).json({ message: "Access Denied: Volunteers only" });
    }

    try {
        const tasks = await Task.find({ assignedTo: req.user.id });
        res.json(tasks);
    } catch (err) {
        console.error("Error fetching assigned tasks:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// Admin/Volunteer: Update task status or details
router.put("/:id", authenticate, async (req, res) => {
    try {
        const task = await Task.findById(req.params.id);
        if (!task) {
            return res.status(404).json({ message: "Task not found" });
        }

        // Only the assigned volunteer or an admin can update the task
        if (req.user.role !== "admin" && req.user.id !== task.assignedTo?.toString()) {
            return res.status(403).json({ message: "Access Denied" });
        }

        const updates = req.body;
        Object.assign(task, updates);
        await task.save();

        res.json({ message: "Task updated successfully", task });
    } catch (err) {
        console.error("Error updating task:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// Volunteer: Accept a task
router.put("/:id/accept", authenticate, async (req, res) => {
    if (req.user.role !== "volunteer") {
        return res.status(403).json({ message: "Access Denied: Volunteers only" });
    }

    try {
        const task = await Task.findById(req.params.id);
        if (!task) {
            return res.status(404).json({ message: "Task not found" });
        }

        if (task.assignedTo) {
            return res.status(400).json({ message: "Task is already assigned to another volunteer" });
        }

        task.assignedTo = req.user.id;
        task.status = "In Progress";
        await task.save();

        res.json({ message: "Task accepted successfully", task });
    } catch (err) {
        console.error("Error accepting task:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// Admin: Assign a task to a volunteer
router.put("/:id/assign", authenticate, async (req, res) => {
    if (req.user.role !== "admin") {
        return res.status(403).json({ message: "Access Denied: Admins only" });
    }

    const { volunteerId } = req.body;

    try {
        const task = await Task.findById(req.params.id);
        if (!task) {
            return res.status(404).json({ message: "Task not found" });
        }

        if (task.assignedTo) {
            return res.status(400).json({ message: "Task is already assigned" });
        }

        task.assignedTo = volunteerId;
        task.status = "In Progress";
        await task.save();

        res.json({ message: "Task assigned successfully", task });
    } catch (err) {
        console.error("Error assigning task:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// Admin: Delete a task
router.delete("/:id", authenticate, async (req, res) => {
    if (req.user.role !== "admin") {
        return res.status(403).json({ message: "Access Denied: Admins only" });
    }

    try {
        const task = await Task.findByIdAndDelete(req.params.id);
        if (!task) {
            return res.status(404).json({ message: "Task not found" });
        }

        res.json({ message: "Task deleted successfully" });
    } catch (err) {
        console.error("Error deleting task:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

module.exports = router;
