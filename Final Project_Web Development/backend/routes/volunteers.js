const express = require("express");
const router = express.Router();
const authenticate = require("../middleware/authenticate");
const Volunteer = require("../models/Volunteer");

// GET all volunteers (Admin only)
router.get("/", authenticate, async (req, res) => {
    try {
        if (req.user.role !== "admin") {
            return res.status(403).json({ message: "Access Denied: Admins only" });
        }
        const volunteers = await Volunteer.find().select("-__v");
        res.json(volunteers);
    } catch (err) {
        console.error("Error fetching volunteers:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// GET a specific volunteer (Admin or the volunteer themselves)
router.get("/:id", authenticate, async (req, res) => {
    try {
        const volunteer = await Volunteer.findById(req.params.id).select("-__v");
        if (!volunteer) {
            return res.status(404).json({ message: "Volunteer not found" });
        }
        // Allow access if admin or the volunteer themselves
        if (req.user.role !== "admin" && req.user.id !== volunteer._id.toString()) {
            return res.status(403).json({ message: "Access Denied" });
        }
        res.json(volunteer);
    } catch (err) {
        console.error("Error fetching volunteer:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// POST create a new volunteer (Public access for onboarding)
router.post("/", async (req, res) => {
    const { name, email, phone, address, availability, skills } = req.body;

    if (!name || !email || !phone) {
        return res.status(400).json({ message: "Name, email, and phone are required" });
    }

    try {
        const newVolunteer = new Volunteer({
            name,
            email,
            phone,
            address: address || null,
            availability: availability || "Part-Time",
            skills: skills || [],
        });
        await newVolunteer.save();
        res.status(201).json({ message: "Volunteer added successfully", volunteer: newVolunteer });
    } catch (err) {
        console.error("Error creating volunteer:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// PUT update a volunteer (Admin or the volunteer themselves)
router.put("/:id", authenticate, async (req, res) => {
    try {
        const volunteer = await Volunteer.findById(req.params.id);
        if (!volunteer) {
            return res.status(404).json({ message: "Volunteer not found" });
        }
        // Allow access if admin or the volunteer themselves
        if (req.user.role !== "admin" && req.user.id !== volunteer._id.toString()) {
            return res.status(403).json({ message: "Access Denied" });
        }
        const updates = req.body;
        const updatedVolunteer = await Volunteer.findByIdAndUpdate(req.params.id, updates, { new: true });
        res.json({ message: "Volunteer updated successfully", volunteer: updatedVolunteer });
    } catch (err) {
        console.error("Error updating volunteer:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// PATCH add a skill to a volunteer's profile (Admin or the volunteer themselves)
router.patch("/:id/add-skill", authenticate, async (req, res) => {
    const { skill } = req.body;

    if (!skill) {
        return res.status(400).json({ message: "Skill is required" });
    }

    try {
        const volunteer = await Volunteer.findById(req.params.id);
        if (!volunteer) {
            return res.status(404).json({ message: "Volunteer not found" });
        }
        if (req.user.role !== "admin" && req.user.id !== volunteer._id.toString()) {
            return res.status(403).json({ message: "Access Denied" });
        }

        volunteer.skills.push(skill);
        await volunteer.save();

        res.json({ message: "Skill added successfully", volunteer });
    } catch (err) {
        console.error("Error adding skill:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

// DELETE a volunteer (Admin only)
router.delete("/:id", authenticate, async (req, res) => {
    try {
        if (req.user.role !== "admin") {
            return res.status(403).json({ message: "Access Denied: Admins only" });
        }
        const deletedVolunteer = await Volunteer.findByIdAndDelete(req.params.id);
        if (!deletedVolunteer) {
            return res.status(404).json({ message: "Volunteer not found" });
        }
        res.json({ message: "Volunteer deleted successfully" });
    } catch (err) {
        console.error("Error deleting volunteer:", err.message);
        res.status(500).json({ message: "Server error", error: err.message });
    }
});

module.exports = router;
