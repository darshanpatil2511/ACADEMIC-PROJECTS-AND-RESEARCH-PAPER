const mongoose = require("mongoose");

// Volunteer Schema
const volunteerSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: [true, "Volunteer name is required"],
      trim: true,
      maxlength: [50, "Name cannot exceed 50 characters"],
    },
    email: {
      type: String,
      required: [true, "Email is required"],
      unique: true,
      trim: true,
      match: [
        /^\w+([.-]?\w+)*@\w+([.-]?\w+)*(\.\w{2,3})+$/,
        "Please provide a valid email address",
      ],
    },
    phone: {
      type: String,
      required: [true, "Phone number is required"],
      match: [
        /^\+?\d{10,15}$/,
        "Please provide a valid phone number (10-15 digits, with optional + prefix)",
      ],
    },
    address: {
      type: String,
      default: null,
      trim: true,
    },
    availability: {
      type: String,
      enum: ["Full-Time", "Part-Time", "Occasional"],
      default: "Part-Time",
    },
    tasks: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "Task", // Reference to Task schema
      },
    ],
    isActive: {
      type: Boolean,
      default: true, // Helps manage volunteer availability
    },
    skills: {
      type: [String],
      default: [], // Allows tracking of volunteer skills
    },
    profileImage: {
      type: String,
      default: null, // Optional field to store profile image URLs
    },
  },
  { timestamps: true } // Automatically adds createdAt and updatedAt fields
);

// Static Methods
volunteerSchema.statics.findAvailableVolunteers = async function () {
  try {
    return await this.find({ isActive: true });
  } catch (error) {
    throw new Error("Error fetching available volunteers.");
  }
};

volunteerSchema.statics.assignTaskToVolunteer = async function (volunteerId, taskId) {
  try {
    const volunteer = await this.findById(volunteerId);
    if (!volunteer) {
      throw new Error("Volunteer not found.");
    }

    volunteer.tasks.push(taskId);
    await volunteer.save();
    return volunteer;
  } catch (error) {
    throw new Error("Error assigning task to volunteer.");
  }
};

// Middleware to clean up tasks when a volunteer is deactivated
volunteerSchema.pre("save", async function (next) {
  if (!this.isActive) {
    this.tasks = []; // Clear tasks for inactive volunteers
  }
  next();
});

module.exports = mongoose.model("Volunteer", volunteerSchema);
