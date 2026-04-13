package com.badas.model;

public class EmergencyCase {
    private int id;
    private String patientName;
    private String location;
    private String symptoms;
    private String emergencyLevel;
    private String status;
    private String assignedResources;
    private String coordinator;
    private String createdAt;
    private String updatedAt;

    public EmergencyCase() {}

    public EmergencyCase(String patientName, String location, String symptoms,
                         String emergencyLevel, String coordinator) {
        this.patientName = patientName;
        this.location = location;
        this.symptoms = symptoms;
        this.emergencyLevel = emergencyLevel;
        this.coordinator = coordinator;
        this.status = "Active";
        this.assignedResources = "";
    }

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getPatientName() { return patientName; }
    public void setPatientName(String patientName) { this.patientName = patientName; }

    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }

    public String getSymptoms() { return symptoms; }
    public void setSymptoms(String symptoms) { this.symptoms = symptoms; }

    public String getEmergencyLevel() { return emergencyLevel; }
    public void setEmergencyLevel(String emergencyLevel) { this.emergencyLevel = emergencyLevel; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getAssignedResources() { return assignedResources; }
    public void setAssignedResources(String assignedResources) { this.assignedResources = assignedResources; }

    public String getCoordinator() { return coordinator; }
    public void setCoordinator(String coordinator) { this.coordinator = coordinator; }

    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }

    public String getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(String updatedAt) { this.updatedAt = updatedAt; }

    @Override
    public String toString() {
        return "EmergencyCase{id=" + id + ", patient='" + patientName + "', level='" + emergencyLevel + "'}";
    }
}
